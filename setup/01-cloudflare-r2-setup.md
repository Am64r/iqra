# Cloudflare R2 Setup Guide

## Step 1: Create Cloudflare Account

1. Go to https://dash.cloudflare.com/sign-up
2. Create a free account
3. Verify your email

## Step 2: Enable R2

1. In the Cloudflare dashboard, click **R2** in the left sidebar
2. Click **Create bucket**
3. Name it: `iqra-audio`
4. Choose a location (Auto is fine)
5. Click **Create bucket**

## Step 3: Enable Public Access

1. Go to your `iqra-audio` bucket
2. Click **Settings**
3. Under **Public access**, click **Allow Access**
4. Note your public bucket URL: `https://pub-{YOUR_HASH}.r2.dev`



## Step 4: Get API Credentials (for uploads)

1. Go to **R2** → **Manage R2 API Tokens**
2. Click **Create API token**
3. Give it a name: `iqra-upload`
4. Permissions: **Object Read & Write**
5. Specify bucket: `iqra-audio`
6. Click **Create API Token**
7. **Save these credentials** - you'll need them:
   - Access Key ID
   - Secret Access Key
   - Endpoint URL (e.g., `https://{account_id}.r2.cloudflarestorage.com`)

## Step 5: Upload Audio Files

### Option A: Using rclone (Recommended for bulk uploads)

```bash
# Install rclone
brew install rclone

# Configure rclone for R2
rclone config

# Choose: n (new remote)
# Name: r2
# Storage: s3
# Provider: Cloudflare
# Access Key ID: (paste your key)
# Secret Access Key: (paste your secret)
# Endpoint: (paste your endpoint)
# Leave other options as default

# Upload your Quran folder
rclone copy ./quran r2:iqra-audio/quran --progress
```

### Option B: Using Wrangler CLI

```bash
# Install wrangler
npm install -g wrangler

# Login
wrangler login

# Upload individual files
wrangler r2 object put iqra-audio/quran/mishary/001_fatiha.mp3 --file ./quran/mishary/001_fatiha.mp3
```

## Step 6: Verify Upload

Your files should be accessible at:
```
https://pub-{YOUR_HASH}.r2.dev/quran/mishary/001_fatiha.mp3
```

## Step 7: Update App Configuration

After setup, update `Iqra/Config/CloudConfig.swift` with your R2 public URL:

```swift
static let r2BaseURL = "https://pub-{YOUR_HASH}.r2.dev"
```

## File Organization

Upload your files with this structure:
```
iqra-audio/
└── quran/
    └── {reciter-slug}/
        ├── 001_fatiha.mp3
        ├── 002_baqarah.mp3
        └── ...
```

Example reciter slugs: `mishary`, `sudais`, `alafasy`
