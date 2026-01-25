# Configuration Guide

## Overview

The `config.yaml` file contains all your personal preferences, training rules, and constraints. This guide explains each section and how to customize it.

**Location**: `config.yaml` in the project root

**Version**: 1.0 (Updated: 2026-01-24)

## File Structure

### 1. Athlete Profile

```yaml
athlete:
  name: "Samuel"
  units: "metric"
  spelling: "American"
```

**What it does**: Basic profile information used throughout the plan generation.

**Customization**:
- `name`: Your name (appears in the plan header)
- `units`: `metric` or `imperial` (for kg vs lbs)
- `spelling`: `American` or `British` (for exercise names and notes)

---

### 2. Goals & Focus Areas

```yaml
goals:
  primary: "strength + aesthetics"
  focus_areas:
    - "arms"
    - "medial delts"
    - "upper chest"
    - "back detail"
```

**What it does**: Defines your training priorities. Claude AI uses this to design supplemental workouts.

**Customization**:
- `primary`: Your main training goal (e.g., "hypertrophy", "strength", "fat loss", etc.)
- `focus_areas`: List of specific body parts or qualities to emphasize

**Examples**:
```yaml
# Powerlifting focus
primary: "maximal strength"
focus_areas:
  - "squat technique"
  - "deadlift grip"
  - "bench press lockout"

# Bodybuilding focus
primary: "muscle hypertrophy"
focus_areas:
  - "legs"
  - "chest width"
  - "back thickness"
```

---

### 3. Reference 1RMs

```yaml
reference_1rms:
  back_squat: 129  # kg
  bench_press: 94  # kg
  deadlift: 168    # kg
```

**What it does**: Provides baseline strength levels for calculating percentages and progressive overload.

**Customization**: Update these as your strength improves. Claude uses these to:
- Calculate appropriate loads for accessory work
- Ensure progressive overload recommendations are realistic
- Balance volume and intensity

---

### 4. Weekly Structure

```yaml
weekly_structure:
  main_days:
    - "Monday"
    - "Wednesday"
    - "Friday"
  main_days_note: "Run Fort workouts exactly as written for that cycle"

  supplemental_days:
    - "Tuesday"
    - "Thursday"
    - "Saturday"
  supplemental_days_note: "Aesthetics + incline walking; must NOT compromise next main day"

  daily_warmup: "McGill Big-3 at top of every day"

  finishers:
    incline_walk: true
    thaw_intensity_note: "THAW intensity must preserve next day performance"

  sauna: "Include after all days when appropriate"
```

**What it does**: Defines your weekly training split and structure.

**Customization**:
- `main_days`: Days for trainer-prescribed workouts (don't change unless your trainer schedule changes)
- `supplemental_days`: Days for AI-designed accessory work
- `daily_warmup`: Warm-up protocol (modify if you have a different preference)
- `finishers`: Post-workout activities

**Example - Different Split**:
```yaml
weekly_structure:
  main_days:
    - "Monday"
    - "Thursday"
  supplemental_days:
    - "Tuesday"
    - "Friday"
    - "Saturday"
  daily_warmup: "Dynamic stretching + activation drills"
```

---

### 5. Hard Rules

```yaml
hard_rules:
  equipment:
    - "No belt on pulls"
    - "Standing calf raises only (NEVER seated)"
    - "No split squats (any variant)"

  biceps:
    - "Never same-grip two days in a row"
    - "Rotate grips: supinated → neutral → pronated"
    - "Keep ~48h before another long-length stimulus (e.g., incline curls)"
    - "Cap biceps hard sets at 10-12 per rolling 4 days"

  spelling: "American spelling only"
```

**What it does**: Absolute constraints that Claude MUST follow. These are non-negotiable rules based on your preferences, injuries, or training philosophy.

**Customization**: Add, remove, or modify rules based on your needs.

**Examples**:
```yaml
hard_rules:
  equipment:
    - "No leg press due to knee issues"
    - "Straps allowed on deadlifts over 80%"
    - "No overhead pressing (shoulder injury)"

  exercise_preferences:
    - "Prefer dumbbells over barbells for chest work"
    - "Always include face pulls for shoulder health"

  biceps:
    - "Keep bicep volume low due to elbow tendinitis"
    - "Hammer curls only (no supinated grip)"
```

---

### 6. Progression Rules

```yaml
progression:
  barbell_main_lifts:
    rule: "If last top set ≤ RPE 9 (≥1 RIR), add ~2.5-5 kg next time or add 1-2 reps within range"
    rounding: "Nearest 0.5 kg"

  dumbbells:
    rule: "Move up one DB step after hitting top of rep range on ≥2 sets clean; otherwise add reps"
    rounding: "Nearest available step"

  cable_machine:
    rule: "When top of range is clean with prescribed tempo/pauses, add one plate next session; otherwise add reps"
```

**What it does**: Defines how to progress loads and volume over time.

**Customization**: Adjust based on your training experience and recovery capacity.

**Examples**:
```yaml
# Conservative progression (for beginners or during a cut)
progression:
  barbell_main_lifts:
    rule: "Add weight only when hitting top of rep range for 3 consecutive sessions at RPE 8"
    rounding: "Nearest 2.5 kg"

# Aggressive progression (for intermediates on a bulk)
progression:
  barbell_main_lifts:
    rule: "If RPE ≤ 8, add 5-10 kg or 2-3 reps next time"
    rounding: "Nearest 1 kg"
```

---

### 7. Swap Library

```yaml
swap_library:
  ab_rollout_cable_bar:
    - "RKC plank"
    - "Hollow-body hold"
    - "Stability-ball rollout"
    - "Cable ab pulldown (lat bar)"

  slider_hamstring_curl:
    - "Swiss-ball leg curl"
    - "Dual-DB towel ham slides"
    - "Machine leg curl"
```

**What it does**: Provides alternative exercises when equipment is unavailable or you want variety.

**Customization**: Add your preferred swaps for exercises you can't or don't want to do.

**Examples**:
```yaml
swap_library:
  barbell_bench_press:
    - "Dumbbell bench press"
    - "Machine chest press"
    - "Push-ups (weighted)"

  pull_ups:
    - "Lat pulldown"
    - "Assisted pull-up machine"
    - "Inverted rows"

  back_squat:
    - "Front squat"
    - "Safety bar squat"
    - "Leg press (if knee-friendly)"
```

---

### 8. Sanity Checks

```yaml
sanity_checks:
  - "No same-grip biceps on consecutive days"
  - "Biceps hard sets ≤ 10-12 per rolling 4 days"
  - "Standing calf raises only"
  - "Triceps attachments varied across Tue/Fri/Sat"
  - "No split squats anywhere"
  - "Carries placed Tuesday at moderate load to preserve Friday grip"
  - "THAW intensity won't trash the next main day"
  - "Sauna included after main days when appropriate"
```

**What it does**: Final validation checks before the plan is finalized. These ensure Claude hasn't violated any rules.

**Customization**: Add checks relevant to your training rules.

**Examples**:
```yaml
sanity_checks:
  - "Total weekly squat volume ≤ 50 reps"
  - "No heavy pressing two days in a row"
  - "At least one dedicated ab/core session per week"
  - "Total weekly cardio ≥ 90 minutes"
  - "Rest day before max effort deadlift day"
```

---

## How to Modify Your Config

### Step 1: Open config.yaml

```bash
# On Mac/Linux
nano config.yaml

# Or use any text editor
open config.yaml
```

### Step 2: Edit the Relevant Section

Follow the YAML syntax:
- Use spaces (NOT tabs) for indentation
- Lists use `-` prefix
- Strings can be quoted or unquoted
- Comments start with `#`

### Step 3: Save and Test

After making changes:

```bash
# Test that the config loads correctly
python test_setup.py
```

If there are syntax errors, the test will tell you.

---

## Common Customizations

### Change Your Training Days

```yaml
weekly_structure:
  main_days:
    - "Tuesday"
    - "Thursday"
    - "Saturday"
  supplemental_days:
    - "Monday"
    - "Wednesday"
    - "Friday"
```

### Add an Injury Constraint

```yaml
hard_rules:
  equipment:
    - "No belt on pulls"
    - "Standing calf raises only"
    - "No split squats (any variant)"
    - "No heavy overhead pressing (shoulder impingement)"  # NEW
```

### Update Your 1RMs

```yaml
reference_1rms:
  back_squat: 135  # Updated from 129
  bench_press: 98   # Updated from 94
  deadlift: 175     # Updated from 168
```

### Change Focus Areas

```yaml
goals:
  primary: "strength + aesthetics"
  focus_areas:
    - "legs"           # Changed from arms
    - "glutes"         # Added
    - "upper chest"    # Kept
    - "back width"     # Changed from back detail
```

---

## Tips

1. **Keep a backup**: Before major changes, copy `config.yaml` to `config.backup.yaml`

2. **Test incrementally**: Make one change at a time and test

3. **Use comments**: Document WHY you have certain rules
   ```yaml
   hard_rules:
     equipment:
       - "No leg extensions"  # Knee pain flares up
   ```

4. **Version your config**: When you make significant changes, note it at the top:
   ```yaml
   # Version: 1.1
   # Last Updated: 2026-02-01
   # Changes: Added leg focus, removed arm emphasis
   ```

5. **Review periodically**: Every 4-6 weeks, review your config and update:
   - 1RMs
   - Focus areas
   - Progression rules (if needed)

---

## Troubleshooting

### "YAML parse error"

- Check for consistent indentation (use spaces, not tabs)
- Make sure strings with special characters are quoted
- Verify colons have a space after them: `key: value` not `key:value`

### "Config key not found"

- Make sure you didn't delete any required sections
- Compare with the original `config.yaml` to see what's missing

### Plan doesn't follow your rules

- Check that your rule is in the right section
- Verify YAML syntax is correct
- Make sure the rule is clear and specific
- Try rewording the rule to be more explicit

---

## Advanced: Understanding How Config is Used

The config flows through the system like this:

```
config.yaml
    ↓
main.py (loads config)
    ↓
plan_generator.py (formats config into AI prompt)
    ↓
Claude API (generates plan following rules)
    ↓
Generated workout plan
```

Claude receives:
1. Your athlete profile
2. All hard rules
3. Focus areas and goals
4. Swap library options
5. Sanity checks to validate against

This ensures your personal constraints are baked into every plan.

---

## Questions?

If you're unsure about a config option:
1. Check the example values in the default config
2. Read the relevant section in this guide
3. Try making a small change and generating a plan to see the effect
4. Revert if it doesn't work as expected

The config is designed to be flexible - experiment and find what works for you!
