# Google Sheets API Setup Guide

This guide will walk you through setting up Google Sheets API access for the Workout Planning Tool.

## Prerequisites

- A Google account
- Your workout tracking Google Sheet

## Step-by-Step Setup

### 1. Create a Google Cloud Project

1. Go to the [Google Cloud Console](https://console.cloud.google.com/)
2. Click "Select a project" at the top
3. Click "NEW PROJECT"
4. Name it something like "Workout Planner"
5. Click "CREATE"

### 2. Enable Google Sheets API

1. In your new project, go to "APIs & Services" > "Library"
2. Search for "Google Sheets API"
3. Click on it and click "ENABLE"

### 3. Create Credentials

1. Go to "APIs & Services" > "Credentials"
2. Click "CREATE CREDENTIALS" > "OAuth client ID"
3. If prompted to configure consent screen:
   - Click "CONFIGURE CONSENT SCREEN"
   - Choose "External" (unless you have a Google Workspace)
   - Click "CREATE"
   - Fill in:
     - App name: "Workout Planner"
     - User support email: your email
     - Developer contact: your email
   - Click "SAVE AND CONTINUE"
   - Click "SAVE AND CONTINUE" on Scopes (no changes needed)
   - Click "SAVE AND CONTINUE" on Test users
   - Click "BACK TO DASHBOARD"
4. Go back to "Credentials" > "CREATE CREDENTIALS" > "OAuth client ID"
5. Select "Desktop app" as the application type
6. Name it "Workout Planner Desktop"
7. Click "CREATE"
8. Click "DOWNLOAD JSON" on the popup (or download from the credentials list)

### 4. Install the Credentials

1. Rename the downloaded file to `credentials.json`
2. Move it to your workout planner project folder (where `main.py` is located)

Your project folder should now look like:
```
Sam's Workout App/
├── credentials.json  ← Your new file here
├── main.py
├── config.yaml
├── ...
```

### 5. First Run Authentication

The first time you run the app:

1. Run `python main.py`
2. A browser window will open asking you to sign in to Google
3. Sign in with your Google account
4. Click "Allow" when asked for permissions
5. The app will save a `token.json` file for future use

**Important**: You only need to do this once. The `token.json` file will be saved for future runs.

### Security Notes

- Keep `credentials.json` and `token.json` private (they're in `.gitignore`)
- These files give access only to read your Google Sheets
- You can revoke access anytime from: https://myaccount.google.com/permissions

## Troubleshooting

### "Access blocked: This app's request is invalid"

This means you need to add yourself as a test user:
1. Go to Google Cloud Console
2. "APIs & Services" > "OAuth consent screen"
3. Scroll to "Test users"
4. Click "ADD USERS"
5. Add your email address

### "The file credentials.json is missing"

Make sure you:
1. Downloaded the JSON file from Google Cloud Console
2. Renamed it to exactly `credentials.json`
3. Placed it in the project root folder (next to `main.py`)

### "Could not automatically determine credentials"

Try deleting `token.json` and running the app again. This will trigger a fresh authentication flow.

## Need Help?

If you run into issues:
1. Double-check each step above
2. Make sure the Google Sheets API is enabled in your project
3. Verify your credentials file is in the right location
4. Check that you're using the correct Google account
