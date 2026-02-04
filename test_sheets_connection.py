#!/usr/bin/env python3
"""
Test Google Sheets connection and verify we can read prior week data
"""

import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'src'))

from sheets_reader import SheetsReader
import yaml
from dotenv import load_dotenv

def test_sheets_connection():
    """Test reading from Google Sheets"""

    print("="*80)
    print("TESTING GOOGLE SHEETS CONNECTION")
    print("="*80)

    # Load config
    load_dotenv()
    with open('config.yaml', 'r') as f:
        config = yaml.safe_load(f)

    print(f"\n✓ Config loaded")
    print(f"  Spreadsheet ID: {config['google_sheets']['spreadsheet_id'][:20]}...")
    print(f"  Sheet name: {config['google_sheets']['sheet_name']}")

    # Initialize reader
    try:
        reader = SheetsReader(
            credentials_file=config['google_sheets']['credentials_file'],
            spreadsheet_id=config['google_sheets']['spreadsheet_id'],
            sheet_name=config['google_sheets']['sheet_name'],
            service_account_file=config.get('google_sheets', {}).get('service_account_file')
        )
        print(f"\n✓ SheetsReader initialized")
    except Exception as e:
        print(f"\n✗ Failed to initialize SheetsReader: {e}")
        return False

    # Authenticate
    try:
        reader.authenticate()
        print(f"✓ Authentication successful")
    except Exception as e:
        print(f"✗ Authentication failed: {e}")
        return False

    # Read prior week supplemental data
    try:
        print(f"\n📖 Reading supplemental exercises from '{config['google_sheets']['sheet_name']}'...")
        supplemental_data = reader.read_prior_week_supplemental()

        if not supplemental_data:
            print(f"⚠️  No supplemental data found (this is OK if it's a new program)")
            return True

        # Count total exercises across all days
        total_exercises = sum(len(exercises) for exercises in supplemental_data.values())
        print(f"✓ Found {total_exercises} supplemental exercises")

        # Show first few exercises from each day
        print(f"\n📋 Sample exercises:")
        for day in ['Tuesday', 'Thursday', 'Saturday']:
            exercises = supplemental_data.get(day, [])
            if exercises:
                print(f"\n  === {day.upper()} ({len(exercises)} exercises) ===")
                for i, ex in enumerate(exercises[:2], 1):  # Show first 2 per day
                    print(f"  {i}. {ex.get('exercise', 'Unknown')}")
                    print(f"     Block: {ex.get('block', '-')}")
                    print(f"     Sets: {ex.get('sets', '-')}")
                    print(f"     Reps: {ex.get('reps', '-')}")
                    print(f"     Load: {ex.get('load', '-')} kg")
                    if ex.get('log'):
                        print(f"     Logged: {ex.get('log', '-')}")
                if len(exercises) > 2:
                    print(f"     ... and {len(exercises) - 2} more exercises")

        # Format for AI
        print(f"\n🤖 Formatting for AI prompt...")
        formatted = reader.format_supplemental_for_ai(supplemental_data)
        print(f"✓ Formatted {len(formatted)} characters for AI")
        print(f"\n📝 Preview of formatted data:")
        print("-" * 80)
        print(formatted[:500])
        if len(formatted) > 500:
            print(f"\n... ({len(formatted) - 500} more characters)")
        print("-" * 80)

        return True

    except Exception as e:
        print(f"✗ Failed to read supplemental data: {e}")
        import traceback
        print(f"\n{traceback.format_exc()}")
        return False

if __name__ == "__main__":
    success = test_sheets_connection()

    print("\n" + "="*80)
    if success:
        print("✅ ALL TESTS PASSED - Ready to generate plans!")
    else:
        print("❌ TESTS FAILED - Check errors above")
    print("="*80)

    sys.exit(0 if success else 1)
