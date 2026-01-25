# Getting Started with Your Workout Planning Tool

## What You've Got

This tool helps you create intelligent weekly workout plans by:
1. Reading your workout history from Google Sheets
2. Taking your 3 trainer workouts (Mon/Wed/Fri from Train Heroic)
3. Accepting your weekly preferences
4. Using Claude AI to generate a complete, balanced weekly plan
5. Saving the plan for easy access

## Complete Setup Guide

Follow these steps in order:

### Step 1: Install Python Dependencies (2 minutes)

Open Terminal, navigate to this folder, and run:

```bash
pip install -r requirements.txt
```

If you get an error, try:
```bash
pip3 install -r requirements.txt
```

### Step 2: Set Up Your Claude API Key (2 minutes)

1. Go to [https://console.anthropic.com/](https://console.anthropic.com/)
2. Sign up or log in
3. Go to "API Keys"
4. Click "Create Key"
5. Copy your key (starts with `sk-ant-`)

Now set up your environment file:

```bash
cp .env.example .env
```

Open `.env` in a text editor and paste your key:
```
ANTHROPIC_API_KEY=sk-ant-your-actual-key-here
```

### Step 3: Set Up Google Sheets Access (10 minutes)

This is the most involved step, but you only do it once.

**Follow the detailed guide**: [docs/google_sheets_setup.md](docs/google_sheets_setup.md)

Quick summary:
1. Create a Google Cloud project
2. Enable Google Sheets API
3. Create OAuth credentials
4. Download as `credentials.json`
5. Place in this folder

### Step 4: Configure Your Sheet ID (1 minute)

Open `config.yaml` and update the `spreadsheet_id`:

Your Google Sheet URL looks like:
```
https://docs.google.com/spreadsheets/d/1S9Bh_f69Hgy4iqgtqT9F-t1CR6eiN9e6xJecyHyDBYU/edit
                                          ^^^^ THIS PART ^^^^
```

Copy that ID into `config.yaml`:
```yaml
google_sheets:
  spreadsheet_id: "YOUR_ID_HERE"
  sheet_name: "Sheet1"  # Update if your sheet tab has a different name
```

### Step 5: Test Your Setup (1 minute)

Run the test script to verify everything is configured:

```bash
python test_setup.py
```

If you see "✓ ALL CHECKS PASSED!", you're ready!

If not, the script will tell you what needs to be fixed.

## First Run

### Authentication Flow

The first time you run the tool:

```bash
python main.py
```

1. A browser window will open
2. Sign in to your Google account
3. Click "Allow" when asked for permissions to read your sheets
4. The browser will say "The authentication flow has completed"
5. Close the browser and return to Terminal

This creates a `token.json` file so you won't need to do this again.

### Complete Your First Plan

The tool will guide you through:

1. **Paste Monday's workout** from Train Heroic
   - Copy the entire workout text
   - Paste it in Terminal
   - Press Enter twice (two empty lines) to finish

2. **Paste Wednesday's workout**
   - Same process
   - Press Enter twice when done

3. **Paste Friday's workout**
   - Same process
   - Press Enter twice when done

4. **Answer preference questions**:
   - Focus area this week?
   - Intensity level?
   - How many additional workout days?
   - Anything to avoid?
   - Other preferences?

5. **Wait for Claude to generate your plan** (~10-20 seconds)

6. **Review your plan** - it will be displayed and saved to `output/`

## Weekly Usage

Once set up, your weekly routine is simple:

### Every Monday (or whenever you plan your week):

1. Open Train Heroic
2. Copy this week's Monday, Wednesday, Friday workouts
3. Run: `python main.py`
4. Paste the 3 workouts
5. Answer the quick preference questions
6. Get your complete weekly plan!

**Time investment**: ~5 minutes per week

## Understanding Your Plan

The generated plan will include:

- **Mon/Wed/Fri**: Your trainer's workouts (unchanged)
- **Other days**: AI-designed complementary workouts based on:
  - Your workout history and progress
  - Your stated focus areas
  - Balance and recovery needs
  - Your intensity preferences

Each workout includes:
- Exercise names
- Sets and reps
- Load guidance
- Rest periods
- Form cues and notes

## Cost

Using Claude API costs approximately:
- **$0.10 - $0.50 per plan** (depending on length and complexity)
- **~$2-3 per month** if you generate one plan per week

## Tips for Best Results

1. **Be specific with preferences**: Instead of "get stronger", try "increase squat strength while maintaining upper body work"

2. **Mention constraints**: "Sore left shoulder - avoid overhead pressing" helps the AI adapt

3. **Save your plans**: Keep them in the `output/` folder to track how your training evolves

4. **Review the history**: The AI reads your last 20 workouts, so keeping your Google Sheet updated helps

5. **Adjust intensity**: If a week's plan feels too hard or easy, note it and adjust the intensity preference next week

## Troubleshooting

### Common Issues

**"ModuleNotFoundError"**
- Run: `pip install -r requirements.txt`

**"credentials.json not found"**
- Complete Step 3 (Google Sheets setup)
- Make sure the file is named exactly `credentials.json`
- It should be in this folder (next to `main.py`)

**"ANTHROPIC_API_KEY not found"**
- Make sure `.env` file exists (copy from `.env.example`)
- Your API key is in the `.env` file
- No spaces around the `=` sign

**"Could not find spreadsheet"**
- Double-check the `spreadsheet_id` in `config.yaml`
- Make sure you have access to the sheet
- Verify you're signed in with the right Google account

**"Access blocked" during Google authentication**
- Add yourself as a test user in Google Cloud Console
- See [docs/google_sheets_setup.md](docs/google_sheets_setup.md) for details

### Still Having Issues?

1. Run `python test_setup.py` to identify what's misconfigured
2. Check the detailed guides in the `docs/` folder
3. Review the error message carefully - it usually tells you what's wrong

## Project Structure

```
Sam's Workout App/
├── main.py                    # Run this to generate plans
├── test_setup.py              # Run this to test setup
├── config.yaml                # Your configuration
├── .env                       # Your API key (create from .env.example)
├── credentials.json           # Google credentials (you download this)
├── requirements.txt           # Python dependencies
│
├── src/                       # Core modules
│   ├── sheets_reader.py       # Reads Google Sheets
│   ├── input_handler.py       # Handles user input
│   └── plan_generator.py      # AI plan generation
│
├── docs/                      # Documentation
│   └── google_sheets_setup.md # Detailed Google setup guide
│
├── output/                    # Your generated plans saved here
│
└── README.md, QUICKSTART.md   # Additional guides
```

## Next Steps

1. Complete the setup steps above
2. Run `python test_setup.py` to verify
3. Run `python main.py` to create your first plan
4. Enjoy your personalized weekly training!

Good luck with your training! 💪
