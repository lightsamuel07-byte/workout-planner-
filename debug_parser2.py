#!/usr/bin/env python3
"""
Debug the full parsing logic
"""

import os
import re

# Read the most recent markdown file
output_dir = 'output'
md_files = [f for f in os.listdir(output_dir) if f.endswith('.md')]
md_files.sort(reverse=True)
latest_md = os.path.join(output_dir, md_files[0])

with open(latest_md, 'r') as f:
    plan_text = f.read()

lines = plan_text.split('\n')

current_day = ""
exercises_found = 0

for i, line in enumerate(lines):
    line = line.rstrip()

    # Detect day headers
    if line.startswith('## ') and any(day in line.upper() for day in ['MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY', 'SATURDAY', 'SUNDAY']):
        current_day = line.replace('## ', '').strip()
        print(f"\n{'='*60}")
        print(f"Found day: {current_day}")
        print(f"{'='*60}")
        continue

    # Look for exercises
    if line.startswith('**') and current_day and '. ' in line:
        exercises_found += 1
        print(f"  ✓ Exercise {exercises_found}: {line[:60]}...")

        # Extract exercise details
        exercise_text = line.replace('**', '').strip()
        if '. ' in exercise_text:
            parts = exercise_text.split('. ', 1)
            if len(parts) == 2 and parts[0] and parts[0][0].isalpha():
                block_label = parts[0].strip()
                exercise_name = parts[1].strip()
                print(f"    Block: {block_label}, Exercise: {exercise_name}")

print(f"\nTotal exercises found: {exercises_found}")
