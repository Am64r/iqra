"""
Iqra YouTube Conversion Server

A FastAPI server that extracts audio from YouTube videos and streams MP3 directly to clients.
Designed to run on Fly.io free tier with auto-sleep.
"""

from fastapi import FastAPI, HTTPException, Query
from fastapi.responses import StreamingResponse
from fastapi.middleware.cors import CORSMiddleware
import yt_dlp
import tempfile
import os
import urllib.parse
import re
import logging
import base64
import shutil
import traceback

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Constants
COOKIES_FILE = "/tmp/youtube_cookies.txt"
CHUNK_SIZE = 8192
MAX_FILENAME_LENGTH = 200

def setup_cookies():
    """Set up cookies file from environment variable if available."""
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

# Try to load cookies on startup
COOKIES_AVAILABLE = setup_cookies()

# Common yt-dlp options for YouTube extraction (used by metadata/debug endpoints)
def get_base_ydl_opts():
    """Get base yt-dlp options with cookies."""
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
    version="1.0.0"
)

# Allow CORS for iOS app
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Regex patterns for YouTube URL validation
YOUTUBE_PATTERNS = [
    r'(https?://)?(www\.)?youtube\.com/watch\?v=[\w-]+',
    r'(https?://)?(www\.)?youtu\.be/[\w-]+',
    r'(https?://)?(www\.)?youtube\.com/shorts/[\w-]+',
    r'(https?://)?music\.youtube\.com/watch\?v=[\w-]+',
]


def is_valid_youtube_url(url: str) -> bool:
    """Validate that the URL is a YouTube URL."""
    for pattern in YOUTUBE_PATTERNS:
        if re.match(pattern, url):
            return True
    return False


def sanitize_filename(filename: str) -> str:
    """Remove unsafe characters from filename."""
    unsafe_chars = ['/', '\\', ':', '*', '?', '"', '<', '>', '|']
    for char in unsafe_chars:
        filename = filename.replace(char, '_')
    return filename[:MAX_FILENAME_LENGTH]


@app.get("/")
async def root():
    """Root endpoint with API info."""
    return {
        "name": "Iqra Conversion Server",
        "version": "1.0.0",
        "endpoints": {
            "/health": "Health check",
            "/metadata": "Get video metadata without downloading",
            "/convert": "Convert YouTube video to MP3 and stream"
        }
    }


@app.get("/health")
async def health():
    """Health check endpoint for Fly.io."""
    deno_path = shutil.which("deno")
    
    # Check cookies file
    cookies_exist = os.path.exists(COOKIES_FILE)
    cookies_size = os.path.getsize(COOKIES_FILE) if cookies_exist else 0
    
    return {
        "status": "ok",
        "version": "7",  # Increment to verify deployment
        "cookies_loaded": COOKIES_AVAILABLE,
        "cookies_file_exists": cookies_exist,
        "cookies_file_size": cookies_size,
        "deno_available": deno_path is not None,
        "deno_path": deno_path
    }


@app.get("/debug-formats")
async def debug_formats(url: str = Query(..., description="YouTube URL")):
    """Debug endpoint to list available formats."""
    if not is_valid_youtube_url(url):
        raise HTTPException(status_code=400, detail="Invalid YouTube URL")
    
    try:
        ydl_opts = get_base_ydl_opts()
        
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(url, download=False)
            formats = info.get('formats', [])
            
            return {
                "title": info.get('title'),
                "total_formats": len(formats),
                "format_ids": [f.get('format_id') for f in formats[:30]],
            }
    except Exception as e:
        return {
            "error": str(e),
            "error_type": type(e).__name__,
            "traceback": traceback.format_exc()[-1000:]
        }


@app.get("/metadata")
async def get_metadata(url: str = Query(..., description="YouTube URL")):
    """
    Get video metadata without downloading.
    Uses async subprocess for non-blocking operation.
    """
    import asyncio
    import json
    
    if not is_valid_youtube_url(url):
        raise HTTPException(
            status_code=400, 
            detail="Invalid YouTube URL. Supported: youtube.com, youtu.be, music.youtube.com"
        )
    
    try:
        cmd = [
            'yt-dlp',
            '--remote-components', 'ejs:github',
            '--cookies', COOKIES_FILE,
            '--skip-download',
            '--print-json',
            url
        ]
        
        process = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )
        
        try:
            stdout, stderr = await asyncio.wait_for(
                process.communicate(),
                timeout=60
            )
        except asyncio.TimeoutError:
            process.kill()
            raise HTTPException(status_code=504, detail="Request timed out")
        
        if process.returncode != 0:
            logger.error(f"Metadata fetch failed: {stderr.decode()}")
            raise HTTPException(status_code=400, detail=f"Could not fetch video: {stderr.decode()[:200]}")
        
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


@app.get("/convert")
async def convert(
    url: str = Query(..., description="YouTube URL"),
    quality: str = Query("192", description="Audio quality (128, 192, 256, 320)")
):
    """
    Convert YouTube video to MP3 and stream directly to client.
    Uses async subprocess for non-blocking operation.
    """
    import asyncio
    import json
    
    if not is_valid_youtube_url(url):
        raise HTTPException(status_code=400, detail="Invalid YouTube URL")
    
    # Validate quality
    valid_qualities = ['128', '192', '256', '320']
    if quality not in valid_qualities:
        quality = '192'
    
    logger.info(f"Converting: {url} at {quality}kbps")
    
    tmpdir = tempfile.mkdtemp()
    output_path = os.path.join(tmpdir, "audio.mp3")
    
    try:
        # Build yt-dlp command with flags we KNOW work
        cmd = [
            'yt-dlp',
            '--remote-components', 'ejs:github',  # The key flag!
            '--cookies', COOKIES_FILE,
            '-x',  # Extract audio
            '--audio-format', 'mp3',
            '--audio-quality', quality + 'K',
            '-o', output_path,
            '--print-json',  # Get metadata as JSON
            url
        ]
        
        logger.info(f"Running: {' '.join(cmd)}")
        
        # Use async subprocess so server stays responsive
        process = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )
        
        try:
            stdout, stderr = await asyncio.wait_for(
                process.communicate(),
                timeout=300  # 5 min timeout
            )
        except asyncio.TimeoutError:
            process.kill()
            raise HTTPException(status_code=504, detail="Conversion timed out")
        
        if process.returncode != 0:
            logger.error(f"yt-dlp failed: {stderr.decode()}")
            raise HTTPException(
                status_code=400,
                detail=f"Could not download video: {stderr.decode()[:500]}"
            )
        
        stdout_text = stdout.decode()
        
        # Parse metadata from JSON output
        try:
            info = json.loads(stdout_text.strip().split('\n')[-1])
            title = info.get('title', 'Unknown')
            artist = info.get('uploader') or info.get('channel') or 'Unknown'
            duration = info.get('duration', 0)
        except (json.JSONDecodeError, IndexError):
            title = 'Unknown'
            artist = 'Unknown'
            duration = 0
        
        if not os.path.exists(output_path):
            # Try to find any mp3 file
            for f in os.listdir(tmpdir):
                if f.endswith('.mp3'):
                    output_path = os.path.join(tmpdir, f)
                    break
            else:
                raise HTTPException(status_code=500, detail="Conversion failed - no output file")
        
        file_size = os.path.getsize(output_path)
        logger.info(f"Conversion complete: {title} ({file_size} bytes)")
        
        def iter_file():
            try:
                with open(output_path, 'rb') as f:
                    while chunk := f.read(CHUNK_SIZE):
                        yield chunk
            finally:
                shutil.rmtree(tmpdir, ignore_errors=True)
        
        safe_title = urllib.parse.quote(sanitize_filename(title), safe='')
        safe_artist = urllib.parse.quote(sanitize_filename(artist), safe='')
        
        return StreamingResponse(
            iter_file(),
            media_type="audio/mpeg",
            headers={
                "Content-Length": str(file_size),
                "X-Track-Title": safe_title,
                "X-Track-Artist": safe_artist,
                "X-Track-Duration": str(duration),
                "Content-Disposition": f'attachment; filename="{safe_title}.mp3"',
                "Cache-Control": "no-cache",
            }
        )
        
    except HTTPException:
        shutil.rmtree(tmpdir, ignore_errors=True)
        raise
    except Exception as e:
        shutil.rmtree(tmpdir, ignore_errors=True)
        logger.error(f"Conversion error: {e}")
        raise HTTPException(status_code=500, detail=f"Conversion failed: {str(e)}")


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080)
