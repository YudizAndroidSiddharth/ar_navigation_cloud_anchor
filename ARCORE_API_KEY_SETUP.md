# ARCore Cloud Anchors API Key Setup Guide

## Problem
The app is currently showing this error:
```
E/ARCore-AnchorServiceClient: INVALID_ARGUMENT: API key not valid. Please pass a valid API key.
E/io.carius.lars.ar_flutter_plugin.AndroidARView: Error uploading anchor, state ERROR_NOT_AUTHORIZED
```

This is because the AndroidManifest.xml still has a placeholder API key.

## Solution: Get Your ARCore Cloud Anchors API Key

### Step 1: Go to Google Cloud Console
1. Open [Google Cloud Console](https://console.cloud.google.com/)
2. Select your project (or create a new one)
   - Your project ID appears to be: `ar-navigation-poc` (from google-services.json)

### Step 2: Enable ARCore API
1. Go to **APIs & Services** > **Library**
2. Search for "ARCore API"
3. Click on **ARCore API**
4. Click **Enable**

### Step 3: Create API Key
1. Go to **APIs & Services** > **Credentials**
2. Click **+ CREATE CREDENTIALS** > **API key**
3. A new API key will be created
4. **Important**: Click on the API key to edit it
5. Under **API restrictions**, select **Restrict key**
6. Choose **ARCore API** from the list
7. Click **Save**

### Step 4: Add API Key to AndroidManifest.xml
1. Open `android/app/src/main/AndroidManifest.xml`
2. Find this line (around line 23):
   ```xml
   <meta-data
       android:name="com.google.android.ar.API_KEY"
       android:value="YOUR_ARCORE_CLOUD_ANCHORS_API_KEY_HERE" />
   ```
3. Replace `YOUR_ARCORE_CLOUD_ANCHORS_API_KEY_HERE` with your actual API key from Step 3
4. Save the file

### Step 5: Rebuild the App
```bash
flutter clean
flutter pub get
flutter run
```

## Verification
After adding the API key:
1. Run the app
2. Navigate to Cloud Anchor Test screen
3. Tap a yellow plane to place an anchor
4. Click "Upload Anchor"
5. You should see a Cloud Anchor ID appear after 10-30 seconds

## Important Notes
- The ARCore Cloud Anchors API key is **different** from the Maps API key
- The API key must be restricted to ARCore API for security
- The API key must be enabled in your Google Cloud project
- Make sure billing is enabled for your Google Cloud project (ARCore API requires billing)

## Current Status
✅ **Working:**
- AR view initialization
- Plane detection (yellow markers)
- Tap detection
- Anchor placement
- Upload button enabling

❌ **Not Working:**
- Cloud anchor upload (needs valid API key)


























