# 💪 Workout Planning Web App

A beautiful web interface for your AI-powered workout planning tool!

## 🚀 Quick Start

### Option 1: Using the Launch Script (Easiest)
```bash
./run_app.sh
```

### Option 2: Manual Launch
```bash
export PATH="/Users/samuellight/Library/Python/3.13/bin:$PATH"
streamlit run app.py
```

The app will automatically open in your default browser at `http://localhost:8501`

## 📱 Features

### ✅ Implemented
- **📊 Dashboard** - Weekly calendar view with current workout schedule
- **🆕 Generate Plan** - Easy interface to paste Fort workouts and generate new plans
- **📋 View Plans** - Browse all your generated workout plans with beautiful formatting
- **📈 Progress** - Track your strength gains and training progress

### 🚧 Coming Soon
- **🏋️ Gym Mode** - Simplified interface for logging during workouts with rest timers
- **📸 Body Comp Tracking** - Upload progress photos
- **📱 Mobile Optimization** - Better phone/tablet experience
- **🔔 Notifications** - Workout reminders
- **📊 Advanced Analytics** - Volume trends, injury risk indicators

## 🎨 Pages Overview

### Dashboard
- Weekly calendar showing Mon-Sun workouts
- Quick stats (volume, PRs, exercises)
- Quick action buttons

### Generate Plan
1. Paste your 3 Fort workouts (Mon/Wed/Fri)
2. Select if it's a new program or continuing
3. Click generate
4. Automatically saved to Google Sheets!

### View Plans
- Select from all your generated plans
- Browse by day with beautiful exercise cards
- See sets, reps, load, rest, and coaching notes
- Link to open in Google Sheets

### Progress
- Main lifts progress charts (Squat, Bench, Deadlift)
- Weekly volume tracking
- Muscle group focus progress
- Achievement badges

## 🔧 Technical Details

### Architecture
- **Frontend**: Streamlit (Python web framework)
- **Backend**: Your existing Python modules (plan_generator, sheets_reader, sheets_writer)
- **Database**: Google Sheets (already integrated!)
- **AI**: Claude Sonnet 4.5 via Anthropic API

### File Structure
```
Sam's Workout App/
├── app.py                  # Main Streamlit app
├── pages/
│   ├── dashboard.py        # Dashboard page
│   ├── generate_plan.py    # Plan generation page
│   ├── view_plans.py       # Plan viewing page
│   └── progress.py         # Progress tracking page
├── src/                    # Your existing backend code
├── output/                 # Generated markdown plans
└── run_app.sh             # Launch script
```

## ⚙️ Configuration

The web app uses your existing configuration:
- `.env` - API keys
- `config.yaml` - Athlete profile, rules, Google Sheets ID
- `credentials.json` - Google OAuth credentials

## 🎯 Usage Tips

1. **Generate Plans Without Using API Tokens**:
   - The "View Plans" page shows existing plans from the `output/` folder
   - Only use "Generate Plan" when you need a new week

2. **Google Sheets Integration**:
   - Plans are automatically written to Google Sheets
   - Use the "Open in Google Sheets" button for quick access

3. **Mobile Access**:
   - Get your local IP: `ifconfig | grep "inet "`
   - Access from phone: `http://YOUR_IP:8501`
   - Must be on same WiFi network

## 🔥 Next Steps

Want to enhance the app? Here are some ideas:

1. **Deploy Online**: Use Streamlit Cloud (free) to access from anywhere
2. **Add Gym Mode**: Simplified logging interface with rest timers
3. **Photo Tracking**: Upload progress photos and compare over time
4. **Export PDFs**: Generate printable workout cards
5. **Apple Health Integration**: Sync workout data

## 💡 Troubleshooting

**App won't start?**
```bash
# Check if Streamlit is installed
python3 -m pip install streamlit

# Check Python path
which python3
```

**Can't find pages?**
- Make sure you're running from the app directory
- Check that `pages/` folder exists with all .py files

**API errors when generating?**
- Check `.env` file has `ANTHROPIC_API_KEY`
- Verify Google credentials are set up
- Test with `python3 main.py` first

## 📞 Support

Questions? The app is built on top of your existing CLI tool, so all the same configurations apply!

---

**Enjoy your new web interface! 💪🏋️‍♂️**
