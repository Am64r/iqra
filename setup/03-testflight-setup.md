# TestFlight Setup Guide

Distribute your app to family and friends via TestFlight.

## Prerequisites

- Apple Developer Account ($99/year) - https://developer.apple.com/programs/
- Xcode with your app configured

## Step 1: Register App ID

1. Go to https://developer.apple.com/account
2. Certificates, Identifiers & Profiles → Identifiers
3. Click **+** to create new
4. Select **App IDs** → Continue
5. Select **App** → Continue
6. Configure:
   - Description: `Iqra`
   - Bundle ID: `com.yourname.iqra` (must match Xcode)
7. Click **Continue** → **Register**

## Step 2: Create App in App Store Connect

1. Go to https://appstoreconnect.apple.com
2. Click **My Apps** → **+** → **New App**
3. Fill in:
   - Platform: **iOS**
   - Name: `Iqra` (or your preferred name)
   - Primary Language: English
   - Bundle ID: Select the one you created
   - SKU: `iqra-1` (any unique identifier)
4. Click **Create**

## Step 3: Archive in Xcode

1. Open your project in Xcode
2. Select **Any iOS Device** as build destination
3. Product → **Archive**
4. Wait for build to complete

## Step 4: Upload to App Store Connect

1. When Archive completes, the Organizer window opens
2. Select your archive → **Distribute App**
3. Select **TestFlight & App Store** → Next
4. Select **Upload** → Next
5. Keep all options checked → Next
6. Select your signing certificate → Next
7. Click **Upload**
8. Wait for upload to complete (may take several minutes)

## Step 5: Complete App Information

In App Store Connect, complete required fields:

### General Information
- App icon (1024x1024 PNG)
- App description
- Privacy Policy URL (can use a simple GitHub gist)

### Build Processing
- Wait for Apple to process your build (~15-30 minutes)
- You'll receive an email when ready

## Step 6: Add Testers

### Internal Testers (Your Team)
1. App Store Connect → Users and Access
2. Add team members with "Developer" or "App Manager" role
3. They can access TestFlight immediately

### External Testers (Family/Friends)
1. Go to your app → TestFlight → External Testing
2. Click **+** to create a test group (e.g., "Family")
3. Click **+** next to Testers to add people by email
4. Submit for Beta App Review (usually approved within 24 hours)

## Step 7: Invite Testers

Once approved:
1. Testers receive email invitation
2. They install TestFlight app from App Store
3. Open invitation link or enter invite code
4. Install your app!

## Updating the App

To push updates:
1. Increment version/build number in Xcode
2. Archive → Distribute → Upload
3. In TestFlight, enable new build for your test groups
4. Testers receive automatic update notification

## TestFlight Limits

- **Internal testers**: Up to 100 (part of your team)
- **External testers**: Up to 10,000
- **Build expiration**: 90 days
- **Test groups**: Unlimited

## Notes for Iqra

Since this app includes YouTube-to-MP3 functionality:
- ✅ OK for personal/family use via TestFlight
- ❌ Not suitable for public App Store release (violates YouTube ToS)
- Keep external testers limited to people you know

## Troubleshooting

### "Missing Compliance" warning
- Click the warning in App Store Connect
- Answer "No" to encryption questions (we don't use custom encryption)

### "Build stuck in processing"
- Usually takes 15-30 minutes
- If over 1 hour, try re-uploading

### "Invalid binary" error
- Check Bundle ID matches App Store Connect
- Ensure all required icons are included
- Try Archive → Validate App first
