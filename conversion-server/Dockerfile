# Iqra Conversion Server Dockerfile
# Optimized for Fly.io free tier (256MB RAM)

FROM python:3.12-slim

# Install ffmpeg, git, and deno (required for yt-dlp YouTube extraction)
RUN apt-get update && \
    apt-get install -y --no-install-recommends ffmpeg curl unzip git && \
    curl -fsSL https://deno.land/install.sh | DENO_INSTALL=/usr/local sh && \
    apt-get remove -y curl unzip && \
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

ENV PATH="/usr/local/bin:$PATH"

# Set working directory
WORKDIR /app

# Install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Install latest yt-dlp nightly with EJS solver for freshest YouTube fixes
RUN pip install --no-cache-dir --upgrade \
    "yt-dlp[default] @ https://github.com/yt-dlp/yt-dlp/archive/master.tar.gz"

# Copy application code
COPY main.py .

# Create non-root user for security
RUN useradd -m -u 1000 appuser && \
    chown -R appuser:appuser /app
USER appuser

# Expose port
EXPOSE 8080

# Health check for Fly.io
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/health')" || exit 1

# Run the application
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
