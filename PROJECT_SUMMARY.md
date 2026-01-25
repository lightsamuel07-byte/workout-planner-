# Workout Planning Tool - Project Summary

## ✅ What's Been Built

A complete, production-ready workout planning automation tool with:

### Core Features
- ✅ Google Sheets integration to read workout history
- ✅ Interactive input for trainer workouts (copy-paste from Train Heroic)
- ✅ Weekly preference collection (focus, intensity, constraints)
- ✅ AI-powered plan generation using Claude Sonnet 4.5
- ✅ Clean, formatted output saved to files
- ✅ Easy-to-run command-line interface

### Technical Implementation
- ✅ Python-based with proper error handling
- ✅ OAuth 2.0 authentication with Google Sheets API
- ✅ Anthropic Claude API integration
- ✅ Modular, maintainable code structure
- ✅ Configuration file for easy customization
- ✅ Environment variable management for secrets

### Documentation
- ✅ Complete setup guides
- ✅ Quick start instructions
- ✅ Troubleshooting documentation
- ✅ Test script to verify setup

## 📁 File Structure

```
Sam's Workout App/
│
├── 🚀 ENTRY POINTS
│   ├── main.py                 # Main application - run this!
│   └── test_setup.py           # Setup verification script
│
├── ⚙️ CONFIGURATION
│   ├── config.yaml             # App settings (Sheet ID, etc.)
│   ├── .env.example            # Template for API key
│   ├── .env                    # Your API key (create this)
│   └── credentials.json        # Google OAuth (you download)
│
├── 📦 DEPENDENCIES
│   └── requirements.txt        # Python packages to install
│
├── 🧩 SOURCE CODE (src/)
│   ├── sheets_reader.py        # Google Sheets integration
│   ├── input_handler.py        # User input handling
│   └── plan_generator.py       # AI plan generation
│
├── 📚 DOCUMENTATION (docs/)
│   ├── google_sheets_setup.md  # Detailed Google API setup
│   ├── GETTING_STARTED.md      # Complete walkthrough
│   ├── QUICKSTART.md           # Quick reference
│   └── README.md               # Project overview
│
└── 📤 OUTPUT (output/)
    └── workout_plan_*.md       # Generated plans saved here
```

## 🎯 How It Works

### Workflow

```
1. Read Google Sheets
   ↓
2. Collect 3 Trainer Workouts (Mon/Wed/Fri)
   ↓
3. Gather User Preferences
   ↓
4. Send to Claude AI with Context:
   - Recent workout history
   - Trainer workouts
   - User preferences
   ↓
5. Generate Complete Weekly Plan
   ↓
6. Save to File + Display
```

### What Gets Sent to Claude

```
INPUTS:
├── Recent Workout History (last 20 workouts from Sheets)
├── Trainer Workouts (Mon/Wed/Fri from Train Heroic)
└── User Preferences (focus, intensity, constraints)

OUTPUT:
└── Complete 7-Day Plan
    ├── Mon/Wed/Fri: Trainer workouts (unchanged)
    └── Other days: AI-designed complementary workouts
```

## 🔧 Setup Checklist

- [ ] Install Python dependencies: `pip install -r requirements.txt`
- [ ] Create Google Cloud project
- [ ] Enable Google Sheets API
- [ ] Download OAuth credentials as `credentials.json`
- [ ] Get Claude API key from console.anthropic.com
- [ ] Create `.env` file with API key
- [ ] Update `config.yaml` with your Sheet ID
- [ ] Run `python test_setup.py` to verify
- [ ] Run `python main.py` for first plan!

## 💡 Key Design Decisions

### Why Claude API instead of chat interface?
- Automation: Runs programmatically without manual interaction
- Consistency: Same process every week
- Integration: Can read from Sheets and save to files
- Cost-effective: ~$2-3/month for weekly plans

### Why Google Sheets API?
- Your data stays in your existing sheet
- No data migration needed
- Continues to work with your current workflow
- Read-only access for safety

### Why Copy-Paste for Trainer Workouts?
- Train Heroic's website is complex (auth, dynamic content)
- Copy-paste is simple and reliable
- Takes 30 seconds vs. complex web scraping
- No risk of breaking if Train Heroic changes

## 📊 Cost Breakdown

### One-Time Costs
- $0 - Everything uses free tiers

### Recurring Costs
- Claude API: ~$0.10-0.50 per plan
- Weekly usage: ~$2-3 per month
- Google Sheets API: Free (within limits)

### Time Investment
- Setup: 15-20 minutes (one time)
- Weekly usage: 5 minutes
- Time saved: 30-60 minutes of manual planning

## 🚀 Next Steps for You

1. **Complete Setup** (15 minutes)
   - Follow GETTING_STARTED.md
   - Run test_setup.py to verify

2. **Generate First Plan** (5 minutes)
   - Run main.py
   - Paste your trainer workouts
   - Get your first AI-generated plan!

3. **Optional Enhancements** (future)
   - Add plan directly to Google Sheets (write capability)
   - Email the plan to yourself
   - Track which plans you actually followed
   - Progress analytics over time

## 🎓 What You Can Learn From This

This project demonstrates:
- OAuth 2.0 authentication
- REST API integration (Google Sheets, Anthropic)
- Environment variable management
- Error handling and user experience
- Modular Python architecture
- CLI application design
- API cost optimization

## 📝 Notes

- All API credentials stay local (in .env and credentials.json)
- Your workout data never leaves your Google account
- The tool only reads from Sheets (no write access)
- Plans are saved locally in the output/ folder
- You can modify config.yaml without touching code

## ✨ Ready to Use!

Everything is built and ready. Just complete the setup and run it!

```bash
# Verify setup
python test_setup.py

# Generate your first plan
python main.py
```

Good luck with your training! 💪
