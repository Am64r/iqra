# Iqra - Quran Audio Library

An iOS app for browsing and playing Quran recitations with YouTube import support.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         iOS App (SwiftUI)                           │
├─────────────────────────────────────────────────────────────────────┤
│  Library View  │  Quran View  │  Imports View  │  Player View       │
├─────────────────────────────────────────────────────────────────────┤
│  CatalogService  │  DownloadManager  │  ConversionService           │
│  AudioPlayerService  │  LocalLibraryService                         │
└───────────────────────────┬─────────────────────────────────────────┘
                            │
                ┌───────────┴───────────┐
                ▼                       ▼
        ┌───────────────┐       ┌───────────────┐
        │ Cloudflare R2 │       │    Fly.io     │
        │  Audio Files  │       │  YT Convert   │
        │  + catalog    │       │    Server     │
        └───────────────┘       └───────────────┘
```

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
│   ├── requirements.txt
│   └── problems_and_fixes/
└── Iqra/
    └── Iqra/
        ├── IqraApp.swift
        ├── Config/
        ├── Models/
        ├── Services/
        └── Views/
```

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

## Conversion Server

Job-based polling to avoid gateway timeouts on long videos:

```
iOS App                              Fly.io Server
   │                                      │
   │──POST /jobs?url=...────────────────▶│
   │◀─────────{job_id: "abc123"}─────────│  (immediate)
   │                                      │
   │──GET /jobs/abc123──────────────────▶│  [converting...]
   │◀─────────{status: "processing"}─────│
   │                                      │
   │──GET /jobs/abc123──────────────────▶│  [done]
   │◀─────────{status: "completed"}──────│
   │                                      │
   │──GET /jobs/abc123/download─────────▶│
   │◀─────────[MP3 stream]───────────────│
```

## Features

- Browse Quran by surah and reciter
- Download tracks for offline playback
- Import audio from YouTube
- Lock screen controls
- Playback speed control
- Search tracks

## Setup

See the [setup guide](setup/) for detailed instructions:

1. [Cloudflare R2 Setup](setup/01-cloudflare-r2-setup.md) - Configure storage for audio files
2. [Generate Catalog](setup/02-generate-catalog.md) - Create track catalog from your MP3s
3. [TestFlight Setup](setup/03-testflight-setup.md) - Distribute via TestFlight (optional)

## Requirements

- iOS 17.0+
- Xcode 15.0+
- Swift 5.9+
- Python 3.12+ (for catalog generation)
- Cloudflare R2 account (free tier works)
- Fly.io account (for conversion server, free tier works)

## Configuration

Before building:

1. Update `Iqra/Iqra/Config/CloudConfig.swift` with your R2 bucket URL
2. Update bundle identifier in Xcode if needed (currently `com.theamrelhady.Iqra`)
3. Deploy conversion server to Fly.io (see `conversion-server/README.md`)

## Adding More Tracks

1. Add MP3s to your local folder
2. Upload to R2
3. Re-run `generate_catalog.py`
4. Upload new `catalog.json`
5. App will see new tracks on refresh

## License

MIT License - see [LICENSE](LICENSE) file for details.
