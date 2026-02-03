# Generate Track Catalog

The app uses a `catalog.json` file in your R2 bucket to know what tracks are available.

## Step 1: Generate the Catalog

Run this from your local Quran folder:

```bash
cd setup/scripts

# Generate catalog.json from your local files
python generate_catalog.py /path/to/your/quran catalog.json
```

**Expected folder structure:**
```
quran/
└── yasser-ad-dossari/
    ├── 001-al-fatihah.mp3
    ├── 002-al-baqarah.mp3
    └── ...
```

**Output:** A `catalog.json` file like:
```json
{
  "version": 1,
  "generated_at": "2026-01-17T...",
  "reciters": [
    {"slug": "yasser-ad-dossari", "name": "Yasser Ad-Dossari"}
  ],
  "tracks": [
    {
      "title": "Al-Fatihah",
      "surah_number": 1,
      "reciter": "yasser-ad-dossari",
      "r2_path": "quran/yasser-ad-dossari/001-al-fatihah.mp3"
    },
    ...
  ]
}
```

## Step 2: Upload to R2

```bash
# Using wrangler
wrangler r2 object put iqra-audio/catalog.json --file catalog.json

# Or using rclone (if configured)
rclone copy catalog.json r2:iqra-audio/
```

## Step 3: Verify

Open in browser:
```
https://pub-{YOUR_HASH}.r2.dev/catalog.json
```

You should see your catalog JSON.

## Adding New Tracks

When you add more files to R2:

1. Add the MP3s to your local folder
2. Upload them to R2
3. Re-run `generate_catalog.py`
4. Re-upload `catalog.json`

That's it! The app will fetch the updated catalog on next launch.

## Optional: Get Track Durations

If you want duration info, install mutagen:

```bash
pip install mutagen
```

The script will automatically extract durations from your MP3 files.
