# Iqra - Personal Audio Library

A personal Quran audio library iOS app with YouTube import support. No database needed - just R2 storage and a JSON catalog.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         iOS App (SwiftUI)                           │
├─────────────────────────────────────────────────────────────────────┤
│  Library View  │  Quran View  │  Imports View  │  Player View       │
├─────────────────────────────────────────────────────────────────────┤
│  CatalogService  │  DownloadManager  │  ConversionService           │
│  AudioPlayerService  │  NowPlayingService  │  LocalLibraryService   │
└───────────────────────────┬─────────────────────────────────────────┘
                            │
                ┌───────────┴───────────┐
                ▼                       ▼
        ┌───────────────┐       ┌───────────────┐
        │ Cloudflare R2 │       │    Fly.io     │
        │  Audio Files  │       │  YT Convert   │
        │  + catalog    │       │    Server     │
        │    FREE       │       │    FREE       │
        └───────────────┘       └───────────────┘
```

## Cost

| Service | Monthly Cost |
|---------|--------------|
| Cloudflare R2 | $0 (10GB free, no egress fees) |
| Fly.io | $0 (free tier) |
| **Cloud Total** | **$0/month** |
| Apple Developer | $99/year |

## Project Structure

```
iqra/
├── README.md
├── setup/
│   ├── 01-cloudflare-r2-setup.md
│   ├── 02-generate-catalog.md
│   ├── 03-testflight-setup.md
│   └── scripts/
│       └── generate_catalog.py
├── conversion-server/
│   ├── main.py
│   ├── Dockerfile
│   ├── fly.toml
│   └── requirements.txt
└── Iqra/
    └── Iqra/
        ├── IqraApp.swift
        ├── Config/
        ├── Models/
        ├── Services/
        └── Views/
```

## Quick Start

### 1. Set Up R2 Storage

Follow [setup/01-cloudflare-r2-setup.md](setup/01-cloudflare-r2-setup.md):
- Create Cloudflare account
- Create R2 bucket
- Upload your Quran MP3 files

### 2. Generate & Upload Catalog

```bash
cd setup/scripts

# Generate catalog from your local files
python generate_catalog.py /path/to/quran catalog.json

# Upload to R2
wrangler r2 object put iqra-audio/catalog.json --file catalog.json
```

### 3. Deploy Conversion Server (for YouTube imports)

```bash
cd conversion-server

fly auth login
fly launch
fly deploy
```

### 4. Build iOS App

1. Open `Iqra/` in Xcode
2. Update `Config/CloudConfig.swift` with your R2 URL
3. Enable Background Audio capability
4. Build and run!

### 5. Distribute via TestFlight

Follow [setup/03-testflight-setup.md](setup/03-testflight-setup.md)

## How It Works

**Catalog Flow:**
```
Your MP3s → generate_catalog.py → catalog.json → R2 → iOS App
```

**Playback Flow:**
```
App fetches catalog.json from R2
User taps track → Download from R2 → Save locally → Play
```

**YouTube Import Flow:**
```
User pastes URL → Fly.io converts → Streams MP3 → Saves to device
```

## Features

- 🎵 Browse Quran by surah and reciter
- 📥 Download tracks for offline playback
- 🔗 Import audio from YouTube
- 🔒 Lock screen controls
- ⏩ Playback speed (0.5x - 2x)
- 🔍 Search tracks

## Adding More Tracks

1. Add MP3s to your local folder
2. Upload to R2
3. Re-run `generate_catalog.py`
4. Upload new `catalog.json`
5. App will see new tracks on refresh

## License

MIT
