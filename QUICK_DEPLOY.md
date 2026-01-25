# 🚀 Quick Deploy Checklist

## 1️⃣ Create GitHub Repo
- Go to: https://github.com/new
- Name: `workout-planner`
- Visibility: **Private**
- Click **Create repository**

## 2️⃣ Push Code
```bash
cd "/Users/samuellight/Desktop/Sam's Workout App"
git remote add origin https://github.com/YOUR_USERNAME/workout-planner.git
git push -u origin main
```

## 3️⃣ Deploy to Streamlit
- Go to: https://share.streamlit.io
- Click **New app**
- Select your `workout-planner` repo
- Main file: `app.py`
- Click **Advanced settings** → **Secrets**

## 4️⃣ Paste Secrets
See `DEPLOYMENT_GUIDE.md` for full secrets.toml content

## 5️⃣ Click Deploy!
Wait 2-3 minutes. Done! 🎉

---

**Full guide:** See `DEPLOYMENT_GUIDE.md`
**Local launch:** Double-click `launch_app.command`
