#!/usr/bin/env python3
"""
Test script for sheets writer - uses existing markdown file
"""

import os
import sys
import yaml

# Add src to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'src'))

from sheets_writer import SheetsWriter
from datetime import datetime, timedelta

# Load config
with open('config.yaml', 'r') as f:
    config = yaml.safe_load(f)

# Read the most recent markdown file
output_dir = 'output'
md_files = [f for f in os.listdir(output_dir) if f.endswith('.md')]
if not md_files:
    print("No markdown files found in output directory")
    sys.exit(1)

# Sort by filename (which includes timestamp)
md_files.sort(reverse=True)
latest_md = os.path.join(output_dir, md_files[0])

print(f"Reading plan from: {latest_md}")

with open(latest_md, 'r') as f:
    plan_text = f.read()

# Calculate next Monday for sheet name (the upcoming week)
today = datetime.now()
days_until_monday = (7 - today.weekday()) % 7
if days_until_monday == 0:  # If today is Monday, use today
    next_monday = today
else:
    next_monday = today + timedelta(days=days_until_monday)
sheet_name = f"Weekly Plan ({next_monday.month}/{next_monday.day}/{next_monday.year})"

print(f"Will write to sheet: {sheet_name}")

# Initialize sheets writer
sheets_writer = SheetsWriter(
    credentials_file=config['google_sheets']['credentials_file'],
    spreadsheet_id=config['google_sheets']['spreadsheet_id'],
    sheet_name=sheet_name
)

# Authenticate and write
print("\nAuthenticating...")
sheets_writer.authenticate()

print("\nWriting to Google Sheets...")
sheets_writer.write_workout_plan(plan_text)

print("\n✓ Done! Check your Google Sheet.")
