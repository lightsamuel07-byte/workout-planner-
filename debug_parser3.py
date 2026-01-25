#!/usr/bin/env python3
"""
Debug with exact same logic as parser
"""

import os

# Read the file
output_dir = 'output'
md_files = [f for f in os.listdir(output_dir) if f.endswith('.md')]
md_files.sort(reverse=True)
latest_md = os.path.join(output_dir, md_files[0])

with open(latest_md, 'r') as f:
    plan_text = f.read()

lines = plan_text.split('\n')
current_day = ""

for i, line in enumerate(lines):
    line = line.rstrip()

    # Detect days
    if line.startswith('## ') and any(day in line.upper() for day in ['MONDAY', 'TUESDAY']):
        current_day = line.replace('## ', '').strip()
        print(f"Set current_day = '{current_day}'")
        continue

    # Check exercise conditions
    if i == 65 or i == 66 or i == 67:  # Around line 66 where first exercise should be
        print(f"\nLine {i}: '{line[:50]}'")
        print(f"  starts with '**': {line.startswith('**')}")
        print(f"  current_day: '{current_day}'")
        print(f"  has '. ': {'. ' in line}")
        print(f"  ALL conditions: {line.startswith('**') and current_day and '. ' in line}")
