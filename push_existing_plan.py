#!/usr/bin/env python3
"""
Push an existing workout plan (markdown) to Google Sheets
Usage: python3 push_existing_plan.py <markdown_file>
"""

import sys
import os
import yaml
from datetime import datetime
from src.sheets_writer import SheetsWriter

def main():
    # Load config
    with open('config.yaml', 'r') as f:
        config = yaml.safe_load(f)

    # Read the markdown file from stdin or clipboard
    print("Paste your workout plan markdown (press Ctrl+D when done):")
    plan_content = sys.stdin.read()

    if not plan_content.strip():
        print("No content provided!")
        return

    # Get current date for sheet name
    today = datetime.now()
    monday = today - datetime.timedelta(days=today.weekday())
    sheet_name = f"(Weekly Plan) {monday.strftime('%-m/%-d/%Y')}"

    print(f"\nPushing plan to sheet: {sheet_name}")

    # Initialize sheets writer
    writer = SheetsWriter(
        credentials_file=config['google_sheets']['credentials_file'],
        spreadsheet_id=config['google_sheets']['spreadsheet_id'],
        service_account_file=config.get('google_sheets', {}).get('service_account_file')
    )

    writer.authenticate()

    # Write to sheets
    writer.write_plan_to_sheet(plan_content, sheet_name)

    print(f"\n✅ Successfully wrote plan to Google Sheets!")
    print(f"Sheet: {sheet_name}")

if __name__ == "__main__":
    main()
