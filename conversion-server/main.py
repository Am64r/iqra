from fastapi import FastAPI, HTTPException, Query, BackgroundTasks
from fastapi.responses import StreamingResponse, FileResponse
from fastapi.middleware.cors import CORSMiddleware
import tempfile
import os
import urllib.parse
import re
import logging
import base64
import contextlib
import shutil
import traceback
import asyncio
import json
import uuid
from datetime import datetime, timedelta
from typing import Optional
from enum import Enum

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

COOKIES_FILE = "/tmp/youtube_cookies.txt"
JOBS_DIR = "/tmp/iqra_jobs"
CHUNK_SIZE = 8192
MAX_FILENAME_LENGTH = 200
JOB_EXPIRY_MINUTES = 30
METADATA_TIMEOUT_SECONDS = int(os.environ.get("METADATA_TIMEOUT_SECONDS", "90"))
CONVERSION_TIMEOUT_SECONDS = int(os.environ.get("CONVERSION_TIMEOUT_SECONDS", "1800"))
MAX_METADATA_CONCURRENCY = int(os.environ.get("MAX_METADATA_CONCURRENCY", "2"))
MAX_CONVERSION_CONCURRENCY = int(os.environ.get("MAX_CONVERSION_CONCURRENCY", "1"))
CLEANUP_INTERVAL_SECONDS = int(os.environ.get("CLEANUP_INTERVAL_SECONDS", "300"))

os.makedirs(JOBS_DIR, exist_ok=True)


class JobStatus(str, Enum):
    PENDING = "pending"
    PROCESSING = "processing"
    COMPLETED = "completed"
    FAILED = "failed"


jobs: dict = {}
cleanup_task: Optional[asyncio.Task] = None


def setup_cookies():
    cookies_b64 = os.environ.get("YOUTUBE_COOKIES_B64")
    if cookies_b64:
        try:
            cookies_content = base64.b64decode(cookies_b64).decode('utf-8')
            with open(COOKIES_FILE, 'w') as f:
                f.write(cookies_content)
            logger.info("YouTube cookies loaded from environment")
            return True
        except Exception as e:
            logger.warning(f"Failed to load cookies: {e}")
    return False


COOKIES_AVAILABLE = setup_cookies()
metadata_semaphore = asyncio.Semaphore(MAX_METADATA_CONCURRENCY)
conversion_semaphore = asyncio.Semaphore(MAX_CONVERSION_CONCURRENCY)


def get_cookie_args():
    if COOKIES_AVAILABLE and os.path.exists(COOKIES_FILE):
        return ['--cookies', COOKIES_FILE]
    return []


def get_retry_args(retries: int):
    return [
        '--retries', str(retries),
        '--fragment-retries', str(retries),
        '--extractor-retries', str(retries),
        '--retry-sleep', '1:5',
        '--socket-timeout', '20',
        '--no-playlist',
    ]


async def run_subprocess(cmd: list, timeout: int, log_output: bool = False):
    process = await asyncio.create_subprocess_exec(
        *cmd,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE
    )

    try:
        if log_output:
            # Stream output in real-time for debugging
            stdout_chunks = []
            stderr_chunks = []
            
            async def read_stream(stream, chunks, prefix):
                async for line in stream:
                    chunks.append(line)
                    logger.info(f"{prefix}: {line.decode().rstrip()}")
            
            await asyncio.wait_for(
                asyncio.gather(
                    read_stream(process.stdout, stdout_chunks, "yt-dlp"),
                    read_stream(process.stderr, stderr_chunks, "yt-dlp stderr"),
                    process.wait()
                ),
                timeout=timeout
            )
            
            return process.returncode, b''.join(stdout_chunks), b''.join(stderr_chunks)
        else:
            stdout, stderr = await asyncio.wait_for(process.communicate(), timeout=timeout)
            return process.returncode, stdout, stderr
    except asyncio.TimeoutError:
        process.kill()
        try:
            await process.wait()
        except Exception:
            pass
        raise


def get_base_ydl_opts():
    opts = {
        'quiet': True,
        'no_warnings': True,
    }
    if COOKIES_AVAILABLE and os.path.exists(COOKIES_FILE):
        opts['cookiefile'] = COOKIES_FILE
    return opts


app = FastAPI(
    title="Iqra Conversion Server",
    description="YouTube to MP3 conversion API",
    version="2.0.0"
)


@app.on_event("startup")
async def start_cleanup_task():
    global cleanup_task
    cleanup_task = asyncio.create_task(cleanup_loop())


@app.on_event("shutdown")
async def stop_cleanup_task():
    global cleanup_task
    if cleanup_task:
        cleanup_task.cancel()
        with contextlib.suppress(asyncio.CancelledError):
            await cleanup_task

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

YOUTUBE_PATTERNS = [
    r'(https?://)?(www\.)?youtube\.com/watch\?v=[\w-]+',
    r'(https?://)?(www\.)?youtu\.be/[\w-]+',
    r'(https?://)?(www\.)?youtube\.com/shorts/[\w-]+',
    r'(https?://)?music\.youtube\.com/watch\?v=[\w-]+',
]


def is_valid_youtube_url(url: str) -> bool:
    for pattern in YOUTUBE_PATTERNS:
        if re.match(pattern, url):
            return True
    return False


def sanitize_filename(filename: str) -> str:
    unsafe_chars = ['/', '\\', ':', '*', '?', '"', '<', '>', '|']
    for char in unsafe_chars:
        filename = filename.replace(char, '_')
    return filename[:MAX_FILENAME_LENGTH]


def cleanup_old_jobs():
    now = datetime.now()
    expired = []
    for job_id, job in jobs.items():
        if now - job['created_at'] > timedelta(minutes=JOB_EXPIRY_MINUTES):
            expired.append(job_id)
    
    for job_id in expired:
        job = jobs.pop(job_id, None)
        if job and job.get('output_dir'):
            shutil.rmtree(job['output_dir'], ignore_errors=True)
        logger.info(f"Cleaned up expired job: {job_id}")


async def cleanup_loop():
    while True:
        try:
            await asyncio.to_thread(cleanup_old_jobs)
        except Exception as exc:
            logger.warning(f"Cleanup loop error: {exc}")
        await asyncio.sleep(CLEANUP_INTERVAL_SECONDS)


@app.get("/")
async def root():
    return {
        "name": "Iqra Conversion Server",
        "version": "2.0.0",
        "endpoints": {
            "/health": "Health check",
            "/metadata": "Get video metadata",
            "POST /jobs": "Start conversion job",
            "GET /jobs/{job_id}": "Poll job status",
            "GET /jobs/{job_id}/download": "Download completed file"
        }
    }


@app.get("/health")
async def health():
    deno_path = shutil.which("deno")
    cookies_exist = os.path.exists(COOKIES_FILE)
    cookies_size = os.path.getsize(COOKIES_FILE) if cookies_exist else 0
    
    return {
        "status": "ok",
        "version": "8",
        "cookies_loaded": COOKIES_AVAILABLE,
        "cookies_file_exists": cookies_exist,
        "cookies_file_size": cookies_size,
        "deno_available": deno_path is not None,
        "deno_path": deno_path,
        "active_jobs": len([j for j in jobs.values() if j['status'] in [JobStatus.PENDING, JobStatus.PROCESSING]])
    }


@app.get("/metadata")
async def get_metadata(url: str = Query(..., description="YouTube URL")):
    if not is_valid_youtube_url(url):
        raise HTTPException(
            status_code=400, 
            detail="Invalid YouTube URL. Supported: youtube.com, youtu.be, music.youtube.com"
        )
    
    try:
        cmd = [
            'yt-dlp',
            '--remote-components', 'ejs:github',
            '--skip-download',
            '--print-json',
            *get_retry_args(3),
            *get_cookie_args(),
            url
        ]

        async with metadata_semaphore:
            try:
                returncode, stdout, stderr = await run_subprocess(cmd, METADATA_TIMEOUT_SECONDS)
            except asyncio.TimeoutError:
                raise HTTPException(status_code=504, detail="Request timed out")

        if returncode != 0:
            stderr_text = stderr.decode()
            logger.error(f"Metadata fetch failed: {stderr_text}")
            raise HTTPException(status_code=400, detail=f"Could not fetch video: {stderr_text[:200]}")

        info = json.loads(stdout.decode().strip().split('\n')[-1])

        return {
            "title": info.get('title'),
            "artist": info.get('uploader') or info.get('channel'),
            "duration": info.get('duration'),
            "thumbnail": info.get('thumbnail'),
            "description": info.get('description', '')[:500] if info.get('description') else None,
            "view_count": info.get('view_count'),
            "upload_date": info.get('upload_date'),
        }
    except json.JSONDecodeError:
        raise HTTPException(status_code=500, detail="Failed to parse video metadata")
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Unexpected error fetching metadata for {url}: {e}")
        raise HTTPException(status_code=500, detail=f"Server error: {str(e)}")


async def run_conversion(job_id: str, url: str, quality: str):
    job = jobs.get(job_id)
    if not job:
        return
    
    job['status'] = JobStatus.PROCESSING
    job['progress'] = "Starting conversion..."
    
    tmpdir = tempfile.mkdtemp(dir=JOBS_DIR)
    job['output_dir'] = tmpdir
    output_path = os.path.join(tmpdir, "audio.mp3")
    
    try:
        cmd = [
            'yt-dlp',
            '--remote-components', 'ejs:github',
            '-f', 'bestaudio',  # Only download audio stream (much faster)
            '-x',
            '--audio-format', 'mp3',
            '--audio-quality', quality + 'K',
            '-o', output_path,
            '--print-json',
            '--newline',
            '--verbose',  # Show detailed progress logs
            '--progress',  # Ensure progress is shown
            *get_retry_args(5),
            *get_cookie_args(),
            url
        ]

        job['progress'] = "Downloading and converting..."

        async with conversion_semaphore:
            try:
                returncode, stdout, stderr = await run_subprocess(cmd, CONVERSION_TIMEOUT_SECONDS, log_output=True)
            except asyncio.TimeoutError:
                job['status'] = JobStatus.FAILED
                job['error'] = "Conversion timed out"
                return

        if returncode != 0:
            stderr_text = stderr.decode()
            logger.error(f"Job {job_id} failed: {stderr_text}")
            job['status'] = JobStatus.FAILED
            job['error'] = f"Conversion failed: {stderr_text[:200]}"
            return
        
        stdout_text = stdout.decode()
        try:
            info = json.loads(stdout_text.strip().split('\n')[-1])
            job['title'] = info.get('title', 'Unknown')
            job['artist'] = info.get('uploader') or info.get('channel') or 'Unknown'
            job['duration'] = info.get('duration', 0)
        except (json.JSONDecodeError, IndexError):
            job['title'] = 'Unknown'
            job['artist'] = 'Unknown'
            job['duration'] = 0
        
        if not os.path.exists(output_path):
            for f in os.listdir(tmpdir):
                if f.endswith('.mp3'):
                    output_path = os.path.join(tmpdir, f)
                    break
            else:
                job['status'] = JobStatus.FAILED
                job['error'] = "No output file produced"
                return
        
        job['output_path'] = output_path
        job['file_size'] = os.path.getsize(output_path)
        job['status'] = JobStatus.COMPLETED
        job['progress'] = "Complete"
        logger.info(f"Job {job_id} completed: {job['title']} ({job['file_size']} bytes)")
        
    except Exception as e:
        logger.error(f"Job {job_id} error: {e}")
        job['status'] = JobStatus.FAILED
        job['error'] = str(e)


@app.post("/jobs")
async def create_job(
    background_tasks: BackgroundTasks,
    url: str = Query(..., description="YouTube URL"),
    quality: str = Query("128", description="Audio quality (128, 192, 256, 320)")
):
    if not is_valid_youtube_url(url):
        raise HTTPException(status_code=400, detail="Invalid YouTube URL")
    
    valid_qualities = ['128', '192', '256', '320']
    if quality not in valid_qualities:
        quality = '128'
    
    cleanup_old_jobs()
    
    job_id = str(uuid.uuid4())
    jobs[job_id] = {
        'id': job_id,
        'url': url,
        'quality': quality,
        'status': JobStatus.PENDING,
        'progress': 'Queued',
        'created_at': datetime.now(),
        'title': None,
        'artist': None,
        'duration': None,
        'output_path': None,
        'output_dir': None,
        'file_size': None,
        'error': None,
    }
    
    background_tasks.add_task(run_conversion, job_id, url, quality)
    
    return {
        "job_id": job_id,
        "status": JobStatus.PENDING,
        "message": "Conversion started"
    }


@app.get("/jobs/{job_id}")
async def get_job_status(job_id: str):
    job = jobs.get(job_id)
    if not job:
        raise HTTPException(status_code=404, detail="Job not found")
    
    logger.info(f"Job {job_id} status: {job['status']} - {job['progress']}")
    
    response = {
        "job_id": job_id,
        "status": job['status'],
        "progress": job['progress'],
    }
    
    if job['status'] == JobStatus.COMPLETED:
        response.update({
            "title": job['title'],
            "artist": job['artist'],
            "duration": job['duration'],
            "file_size": job['file_size'],
        })
    elif job['status'] == JobStatus.FAILED:
        response['error'] = job['error']
    
    return response


@app.get("/jobs/{job_id}/download")
async def download_job(job_id: str):
    job = jobs.get(job_id)
    if not job:
        raise HTTPException(status_code=404, detail="Job not found")
    
    if job['status'] != JobStatus.COMPLETED:
        raise HTTPException(
            status_code=400, 
            detail=f"Job not ready for download. Status: {job['status']}"
        )
    
    output_path = job.get('output_path')
    if not output_path or not os.path.exists(output_path):
        raise HTTPException(status_code=404, detail="Output file not found")
    
    safe_title = urllib.parse.quote(sanitize_filename(job['title']), safe='')
    safe_artist = urllib.parse.quote(sanitize_filename(job['artist']), safe='')
    
    def iter_file():
        try:
            with open(output_path, 'rb') as f:
                while chunk := f.read(CHUNK_SIZE):
                    yield chunk
        finally:
            if job.get('output_dir'):
                shutil.rmtree(job['output_dir'], ignore_errors=True)
            jobs.pop(job_id, None)
    
    return StreamingResponse(
        iter_file(),
        media_type="audio/mpeg",
        headers={
            "Content-Length": str(job['file_size']),
            "X-Track-Title": safe_title,
            "X-Track-Artist": safe_artist,
            "X-Track-Duration": str(job['duration']),
            "Content-Disposition": f'attachment; filename="{safe_title}.mp3"',
            "Cache-Control": "no-cache",
        }
    )


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080)
