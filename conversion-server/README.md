# Iqra Conversion Server

YouTube to MP3 conversion API built with FastAPI and yt-dlp.

## Local Development

```bash
# Install dependencies
pip install -r requirements.txt

# Make sure ffmpeg is installed
brew install ffmpeg  # macOS
# or: apt-get install ffmpeg  # Linux

# Run the server
python main.py
# or: uvicorn main:app --reload

# Server runs at http://localhost:8080
```

## API Endpoints

### GET /health
Health check for monitoring.

### GET /metadata?url={youtube_url}
Get video metadata without downloading.

**Response:**
```json
{
  "title": "Video Title",
  "artist": "Channel Name",
  "duration": 180,
  "thumbnail": "https://..."
}
```

### GET /convert?url={youtube_url}&quality={128|192|256|320}
Convert YouTube video to MP3 and stream.

**Response:** Streams MP3 binary with headers:
- `X-Track-Title`: URL-encoded title
- `X-Track-Artist`: URL-encoded artist
- `X-Track-Duration`: Duration in seconds
- `Content-Length`: File size in bytes

## Deploy to Fly.io

### First-time setup

```bash
# Install Fly CLI
brew install flyctl  # macOS
# or: curl -L https://fly.io/install.sh | sh

# Login
fly auth login

# Create app (from this directory)
fly launch

# This will:
# - Create the app
# - Set up the region
# - Deploy the first version
```

### Subsequent deployments

```bash
fly deploy
```

### View logs

```bash
fly logs
```

### Check status

```bash
fly status
```

## Environment

The server uses Fly.io's free tier:
- Auto-sleeps when idle
- Wakes on first request (~2-3s cold start)
- 512MB RAM
- 160GB bandwidth/month

## Testing

```bash
# Test health
curl http://localhost:8080/health

# Test metadata
curl "http://localhost:8080/metadata?url=https://www.youtube.com/watch?v=dQw4w9WgXcQ"

# Test conversion (downloads file)
curl -o test.mp3 "http://localhost:8080/convert?url=https://www.youtube.com/watch?v=dQw4w9WgXcQ"
```
