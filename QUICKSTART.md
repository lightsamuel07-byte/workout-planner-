# Quick Start Guide

Get your Workout Planning Tool up and running in 5 minutes!

## Setup (One-Time Only)

### 1. Install Python Dependencies

Open Terminal and navigate to this folder, then run:

```bash
pip install -r requirements.txt
```

Or if you use `pip3`:

```bash
pip3 install -r requirements.txt
```

### 2. Set Up Google Sheets Access

Follow the detailed guide: [docs/google_sheets_setup.md](docs/google_sheets_setup.md)

Quick summary:
1. Create a Google Cloud project
2. Enable Google Sheets API
3. Download OAuth credentials as `credentials.json`
4. Place `credentials.json` in this folder

### 3. Add Your Claude API Key

1. Copy the example environment file:
   ```bash
   cp .env.example .env
   ```

2. Get your API key from [Anthropic Console](https://console.anthropic.com/)

3. Open `.env` in a text editor and add your key:
   ```
   ANTHROPIC_API_KEY=sk-ant-your-actual-key-here
   ```

### 4. Verify Your Config

Open `config.yaml` and verify:
- `spreadsheet_id` matches your Google Sheet ID
- `sheet_name` matches your sheet's tab name (default: "Sheet1")

Your Google Sheet ID is in the URL:
```
https://docs.google.com/spreadsheets/d/[THIS_IS_YOUR_ID]/edit
```

## Running the Tool

### Every Week

1. Open Terminal in this folder

2. Run the tool:
   ```bash
   python main.py
   ```
   Or:
   ```bash
   python3 main.py
   ```

3. Follow the prompts:
   - The tool will authenticate with Google Sheets (first time only)
   - Paste your Monday workout from Train Heroic, press Enter twice
   - Paste your Wednesday workout, press Enter twice
   - Paste your Friday workout, press Enter twice
   - Answer the preference questions
   - Wait for Claude to generate your plan

4. Your plan will be saved to the `output/` folder and displayed on screen

## Example Weekly Workflow

**Monday morning:**
1. Open Train Heroic and view this week's workouts
2. Copy Monday's workout
3. Run `python main.py`
4. Paste Monday's workout, press Enter twice
5. Copy and paste Wednesday's workout, press Enter twice
6. Copy and paste Friday's workout, press Enter twice
7. Answer preference questions (focus, intensity, etc.)
8. Get your complete weekly plan!

## Troubleshooting

### "No module named 'google'"
You need to install dependencies:
```bash
pip install -r requirements.txt
```

### "credentials.json not found"
Follow the Google Sheets setup guide in `docs/google_sheets_setup.md`

### "ANTHROPIC_API_KEY not found"
Make sure you:
1. Created a `.env` file (copy from `.env.example`)
2. Added your API key to it
3. The key starts with `sk-ant-`

### "Could not find spreadsheet"
Check that the `spreadsheet_id` in `config.yaml` matches your Google Sheet's ID from the URL

## Cost Estimate

Each workout plan generation costs approximately:
- **$0.10 - $0.50** depending on complexity
- Based on Claude Sonnet 4.5 pricing

Running this once a week = **~$2-3 per month**

## Tips

- Save your generated plans to compare progress over weeks
- You can edit `config.yaml` to change default preferences
- Plans are saved with timestamps in the `output/` folder
- You can copy the plan directly into your Google Sheet or print it

## Need Help?

Check the full README.md or the detailed documentation in the `docs/` folder.
