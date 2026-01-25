#!/usr/bin/env python3
"""
Verify the Google Sheet content
"""

import sys
import os
import yaml

sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'src'))

from googleapiclient.discovery import build
from google.oauth2.credentials import Credentials

# Load config
with open('config.yaml', 'r') as f:
    config = yaml.safe_load(f)

creds = Credentials.from_authorized_user_file('token.json')
service = build('sheets', 'v4', credentials=creds)

# Read the sheet
range_name = 'Weekly Plan (1/26/2026)!A1:H100'
result = service.spreadsheets().values().get(
    spreadsheetId=config['google_sheets']['spreadsheet_id'],
    range=range_name
).execute()

values = result.get('values', [])

print(f'Total rows read: {len(values)}')
print('\n' + '='*80)
print('SHEET CONTENTS')
print('='*80)

exercise_count = 0
for i, row in enumerate(values, 1):
    if len(row) > 0:
        # Count exercises (rows with a block label in column A)
        if len(row) >= 2 and row[0] and row[1]:
            if row[0] not in ['Block', 'Workout Plan - Generated January 24, 2026 at 09:57 AM', '']:
                if not row[0].startswith('##') and not row[0].endswith('(Upper Body)'):
                    exercise_count += 1

        # Print first 2 columns for readability
        display_row = row[:2] if len(row) >= 2 else row
        print(f'{i:3d}: {display_row}')

print('\n' + '='*80)
print(f'Total exercises counted: {exercise_count}')
print('='*80)
