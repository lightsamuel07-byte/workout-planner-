# 🎯 START HERE - Your Workout Planning Tool

## ✅ What's Ready

Your complete workout planning automation tool is built and ready to use!

**Location**: `Sam's Workout App` folder on your Desktop

## 🚀 Quick Setup (3 Steps)

### Step 1: Install Python Packages (2 min)

Open Terminal in this folder and run:

```bash
pip install -r requirements.txt
```

### Step 2: Get Your API Keys (5 min)

**A. Claude API Key:**
1. Visit: https://console.anthropic.com/
2. Create an account / sign in
3. Get an API key
4. Run: `cp .env.example .env`
5. Edit `.env` and add your key

**B. Google Sheets Access:**
1. Follow the guide: `docs/google_sheets_setup.md`
2. Download `credentials.json`
3. Place it in this folder

### Step 3: Configure Your Sheet (1 min)

Edit `config.yaml` and update your Google Sheets ID:

```yaml
google_sheets:
  spreadsheet_id: "YOUR_SHEET_ID_FROM_URL"
```

## ✅ Verify Setup

```bash
python test_setup.py
```

Should show: "✓ ALL CHECKS PASSED!"

## 🎉 Generate Your First Plan

```bash
python main.py
```

Then:
1. Paste Monday's workout from Train Heroic → Press Enter twice
2. Paste Wednesday's workout → Press Enter twice
3. Paste Friday's workout → Press Enter twice
4. Answer preference questions
5. Get your complete weekly plan!

## 📚 Documentation Guide

**Start with these in order:**

1. **START_HERE.md** ← You are here!
2. **GETTING_STARTED.md** - Complete setup walkthrough
3. **QUICKSTART.md** - Quick reference for later
4. **docs/google_sheets_setup.md** - Detailed Google API setup

**Reference:**
- **PROJECT_SUMMARY.md** - Technical overview
- **README.md** - Project description

## 🆘 Need Help?

**Run the setup test:**
```bash
python test_setup.py
```

It will tell you exactly what's missing or misconfigured.

**Common issues:**
- "Module not found" → Run `pip install -r requirements.txt`
- "credentials.json not found" → Follow `docs/google_sheets_setup.md`
- "API key not found" → Create `.env` file with your Anthropic API key

## 💰 Cost

- Setup: Free
- Weekly usage: ~$0.10-0.50 per plan (Claude API)
- Monthly: ~$2-3 if you generate 1 plan per week

## ⏱️ Time Investment

- **Setup**: 15-20 minutes (one time)
- **Weekly use**: 5 minutes
- **Time saved**: 30-60 minutes of manual planning each week

## 🎯 Your Next Action

Choose one:

**Option A - Ready to set up now?**
→ Open `GETTING_STARTED.md` and follow the steps

**Option B - Want a quick overview first?**
→ Open `PROJECT_SUMMARY.md` to see how it works

**Option C - Just want to try it?**
→ Run the 3 setup steps above, then `python main.py`

---

**Questions?** All the documentation is in this folder. Start with GETTING_STARTED.md for the complete walkthrough.

Let's get you a personalized workout plan! 💪
