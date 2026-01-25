#!/usr/bin/env python3
"""
Debug the parser to see what's happening
"""

import os

# Read the most recent markdown file
output_dir = 'output'
md_files = [f for f in os.listdir(output_dir) if f.endswith('.md')]
md_files.sort(reverse=True)
latest_md = os.path.join(output_dir, md_files[0])

with open(latest_md, 'r') as f:
    lines = f.readlines()

print("Looking for exercise patterns...")
print("=" * 60)

for i, line in enumerate(lines[:100]):  # First 100 lines
    line = line.rstrip()

    # Check for day headers
    if line.startswith('## '):
        print(f"Line {i}: DAY HEADER: {line}")

    # Check for section headers
    elif line.startswith('### '):
        print(f"Line {i}: SECTION: {line}")

    # Check for exercises with **
    elif line.startswith('**') and '. ' in line:
        print(f"Line {i}: EXERCISE?: {line}")
        print(f"  -> Has '**' at start: {line.startswith('**')}")
        print(f"  -> Has '. ' in line: {'. ' in line}")
