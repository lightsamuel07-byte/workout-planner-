# Workout Planning Automation Tool

**Version 1.0** | Updated: 2026-01-24

An intelligent, personalized workout planning assistant that combines your trainer's programming with AI-powered supplemental workouts.

## What It Does

- **Reads your workout history** from Google Sheets to understand your training patterns
- **Incorporates trainer workouts** from Train Heroic (Mon/Wed/Fri) exactly as prescribed
- **Generates intelligent supplemental days** (Tue/Thu/Sat) using Claude AI
- **Follows your personal rules** - exercise preferences, injury constraints, progression protocols
- **Respects your focus areas** - arms, delts, chest, back, or whatever you're prioritizing
- **Outputs complete weekly plans** with exercises, sets, reps, loads, and coaching notes

## Key Features

### Personalized Configuration
- **Athlete profile** with your name, units (metric/imperial), spelling preferences
- **Training goals** and focus areas (strength, aesthetics, specific body parts)
- **1RM references** for intelligent load calculations
- **Hard rules** - exercises to avoid, equipment preferences, volume caps
- **Progression protocols** - how to advance weight and reps over time
- **Swap library** - alternative exercises when equipment isn't available

### Intelligent Planning
- Preserves trainer workouts exactly as written (non-negotiable)
- Fills supplemental days with complementary work
- Balances muscle groups and recovery
- Enforces sanity checks (grip rotation, volume limits, intensity management)
- Includes warm-ups, finishers, and recovery protocols

### Easy to Use
- One-time setup (15-20 minutes)
- Weekly usage: 5 minutes
- Copy-paste workouts from Train Heroic
- Answer quick preference questions
- Get a complete 7-day plan

## Quick Start

See **[START_HERE.md](START_HERE.md)** for the complete setup walkthrough.

### Three-Step Setup

1. **Install dependencies**
   ```bash
   pip install -r requirements.txt
   ```

2. **Configure API access**
   - Get Claude API key from [console.anthropic.com](https://console.anthropic.com/)
   - Set up Google Sheets API (see `docs/google_sheets_setup.md`)
   - Create `.env` file with your API key

3. **Update config.yaml**
   - Add your Google Sheets ID
   - Customize athlete profile, goals, and rules
   - See `docs/configuration_guide.md` for details

### Verify Setup

```bash
python test_setup.py
```

Should show: "✓ ALL CHECKS PASSED!"

### Generate Your First Plan

```bash
python main.py
```

## Documentation

| Document | Purpose |
|----------|---------|
| **[START_HERE.md](START_HERE.md)** | First stop - quick setup overview |
| **[GETTING_STARTED.md](GETTING_STARTED.md)** | Complete setup walkthrough |
| **[QUICKSTART.md](QUICKSTART.md)** | Quick reference for weekly use |
| **[PROJECT_SUMMARY.md](PROJECT_SUMMARY.md)** | Technical overview and architecture |
| **[docs/google_sheets_setup.md](docs/google_sheets_setup.md)** | Detailed Google API setup |
| **[docs/configuration_guide.md](docs/configuration_guide.md)** | Complete config.yaml reference |

## Configuration Highlights

Your `config.yaml` includes:

### Athlete Profile
```yaml
athlete:
  name: "Samuel"
  units: "metric"
  spelling: "American"
```

### Goals & Focus
```yaml
goals:
  primary: "strength + aesthetics"
  focus_areas:
    - "arms"
    - "medial delts"
    - "upper chest"
    - "back detail"
```

### Hard Rules
```yaml
hard_rules:
  equipment:
    - "No belt on pulls"
    - "Standing calf raises only"
    - "No split squats"
  biceps:
    - "Never same-grip two days in a row"
    - "Rotate grips: supinated → neutral → pronated"
    - "Cap hard sets at 10-12 per rolling 4 days"
```

See **[docs/configuration_guide.md](docs/configuration_guide.md)** for complete customization options.

## Project Structure

```
Sam's Workout App/
├── main.py                          # Run this to generate plans
├── test_setup.py                    # Verify your setup
├── config.yaml                      # Your personalized configuration
├── .env                             # Your API key (create from .env.example)
├── credentials.json                 # Google OAuth (you download this)
│
├── src/                             # Core application modules
│   ├── sheets_reader.py             # Google Sheets integration
│   ├── plan_generator.py            # AI plan generation with Claude
│   └── input_handler.py             # User input collection
│
├── docs/                            # Documentation
│   ├── google_sheets_setup.md       # Google API setup guide
│   └── configuration_guide.md       # Config reference
│
├── output/                          # Generated workout plans
│   └── workout_plan_YYYYMMDD.md
│
└── [Documentation files]
    ├── START_HERE.md
    ├── GETTING_STARTED.md
    ├── QUICKSTART.md
    └── PROJECT_SUMMARY.md
```

## How It Works

```
1. Read Google Sheets
   ↓ (Your recent workout history)

2. Collect Trainer Workouts
   ↓ (Copy-paste from Train Heroic)

3. Gather Weekly Preferences
   ↓ (Focus, intensity, constraints)

4. Generate with Claude AI
   ↓ (Following all your rules and preferences)

5. Output Complete Plan
   └─→ Saved to output/ folder
```

## Cost

- **Setup**: Free (uses free tiers)
- **Per plan**: ~$0.10-0.50 (Claude API usage)
- **Monthly**: ~$2-3 (generating 1 plan per week)

## Weekly Workflow

Every Monday (or whenever you plan your week):

1. Open Train Heroic
2. Copy Monday's workout
3. Run `python main.py`
4. Paste Monday workout → Enter twice
5. Paste Wednesday workout → Enter twice
6. Paste Friday workout → Enter twice
7. Answer preference questions
8. Get your complete 7-day plan (5 minutes total)

## Example Output

The generated plan includes:

- **Monday/Wednesday/Friday**: Your trainer's workouts (unchanged)
- **Tuesday/Thursday/Saturday**: AI-designed supplemental workouts
  - Exercises with sets, reps, load guidance
  - Grip rotations tracked for biceps
  - Accessories for your focus areas
  - Finishers (incline walk, etc.)
- **Sunday**: Active recovery or rest
- **Weekly notes**: Progression guidance, form cues, recovery tips

## Customization

All customization happens in `config.yaml`:

- Update your 1RMs as you get stronger
- Change focus areas when priorities shift
- Add injury constraints as needed
- Modify progression rules for different phases
- Add preferred exercise swaps

See **[docs/configuration_guide.md](docs/configuration_guide.md)** for details.

## Requirements

- Python 3.7+
- Google account (for Sheets access)
- Anthropic API key (for Claude)
- Internet connection

## Support

- **Setup issues**: Run `python test_setup.py` for diagnostics
- **Google Sheets auth**: See `docs/google_sheets_setup.md`
- **Config questions**: See `docs/configuration_guide.md`
- **General help**: Check `GETTING_STARTED.md`

## License

Personal use project. All training content from "The Fort" remains property of the trainer.

## Credits

- Powered by [Anthropic Claude](https://www.anthropic.com/)
- Google Sheets API for workout history tracking
- Designed for "The Fort" training programs
