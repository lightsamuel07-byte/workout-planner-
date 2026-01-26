# 🚀 Deployment Guide: Streamlit Community Cloud

This guide will help you deploy your workout planning app to Streamlit Community Cloud (100% free).

## ✅ Pre-Deployment Checklist

- [x] Git repository initialized
- [x] First commit created
- [x] Secrets excluded from git (.env, credentials.json)
- [x] Code updated to use Streamlit secrets
- [x] requirements.txt created

## 📋 Step 1: Create GitHub Repository

1. Go to https://github.com/new
2. Fill in the details:
   - **Repository name**: `workout-planner` (or your choice)
   - **Description**: "AI-powered workout planning app"
   - **Visibility**: Choose **Private** (recommended for personal app)
   - **DO NOT** initialize with README, .gitignore, or license (we already have these)
3. Click **Create repository**

## 📤 Step 2: Push Code to GitHub

Copy and paste these commands in Terminal:

```bash
cd "/Users/samuellight/Desktop/Sam's Workout App"
git remote add origin https://github.com/YOUR_USERNAME/workout-planner.git
git branch -M main
git push -u origin main
```

Replace `YOUR_USERNAME` with your actual GitHub username.

## 🔐 Step 3: Prepare Your Secrets

You'll need to create a secrets.toml file with your actual credentials. The file should follow this format:

**SECRETS.TOML FORMAT:**

```toml
# Claude API Key (get from https://console.anthropic.com/settings/keys)
ANTHROPIC_API_KEY = "your-api-key-here"

# Google Sheets OAuth Credentials (from your credentials.json file)
[gcp_oauth]
client_id = "your-client-id"
project_id = "your-project-id"
auth_uri = "https://accounts.google.com/o/oauth2/auth"
token_uri = "https://oauth2.googleapis.com/token"
auth_provider_x509_cert_url = "https://www.googleapis.com/oauth2/v1/certs"
client_secret = "your-client-secret"
redirect_uris = ["http://localhost"]
```

⚠️ **IMPORTANT**:
- Replace all "your-xxx-here" placeholders with your actual credentials
- Get your credentials from your local `.env` and `credentials.json` files
- Never commit this content to GitHub!

## 🌐 Step 4: Deploy to Streamlit Cloud

1. Go to https://share.streamlit.io
2. Sign in with your GitHub account
3. Click **New app**
4. Fill in the deployment settings:
   - **Repository**: Select your `workout-planner` repo
   - **Branch**: `main`
   - **Main file path**: `app.py`
   - **App URL**: Choose a custom URL (e.g., `sams-workout-planner`)

## 🔒 Step 5: Add Secrets

1. In the deployment page, click **Advanced settings**
2. Find the **Secrets** section
3. Paste the entire SECRETS.TOML content from Step 3
4. Click **Save**

## 🚀 Step 6: Deploy!

1. Click **Deploy**
2. Wait 2-3 minutes for the app to build and deploy
3. Your app will be live at: `https://YOUR-APP-NAME.streamlit.app`

## 🔐 Step 7: First-Time Google Authentication

The first time you use the app in Streamlit Cloud, you'll need to authenticate with Google:

1. Navigate to the **Generate Plan** page
2. Click **Generate Plan**
3. A Google OAuth window will open
4. Sign in and grant permissions
5. After authentication, you'll need to manually save the token to secrets (one-time only)

**To save the token:**
1. The app will show you the token JSON after authentication
2. Go to Streamlit Cloud app settings → Secrets
3. Add this section to your secrets.toml:

```toml
[gcp_token]
token = "YOUR_ACCESS_TOKEN"
refresh_token = "YOUR_REFRESH_TOKEN"
token_uri = "https://oauth2.googleapis.com/token"
client_id = "YOUR_CLIENT_ID"
client_secret = "YOUR_CLIENT_SECRET"
scopes = ["https://www.googleapis.com/auth/spreadsheets"]
```

## ✅ Verify Deployment

Test these features:
- [ ] App loads successfully
- [ ] Dashboard shows properly
- [ ] Generate Plan page loads Fort workout inputs
- [ ] Google Sheets connection works
- [ ] Workout plan generation works
- [ ] Plan is written to Google Sheets

## 🔄 Making Updates

Whenever you want to update your deployed app:

```bash
cd "/Users/samuellight/Desktop/Sam's Workout App"
git add -A
git commit -m "Describe your changes"
git push
```

Streamlit Cloud will automatically redeploy within 1-2 minutes.

## 💰 Cost

- **Streamlit Community Cloud**: $0/month (free forever)
- **Claude API**: ~$0.30 per workout plan generated
- **Google Sheets API**: Free
- **Total monthly cost**: ~$1.20/month (4 plans per month)

## 🆘 Troubleshooting

**App won't start:**
- Check the logs in Streamlit Cloud dashboard
- Verify all secrets are correctly formatted

**API key error:**
- Make sure ANTHROPIC_API_KEY is in secrets.toml
- Check for extra spaces or quotes

**Google Sheets error:**
- Verify gcp_oauth section is correct
- Make sure you've completed first-time authentication

**Need help?**
- Streamlit Community: https://discuss.streamlit.io
- Your local app still works with: `./launch_app.command`

## 🎉 You're Done!

Your workout planning app is now live on the web and accessible from any device!

**Next steps:**
- Bookmark your app URL
- Generate your first plan
- Share the URL (keep it private if needed)
