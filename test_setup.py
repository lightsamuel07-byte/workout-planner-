#!/usr/bin/env python3
"""
Test script to verify the setup is correct.
Run this before using main.py for the first time.
"""

import os
import sys

def test_python_version():
    """Check Python version."""
    print("Checking Python version...")
    version = sys.version_info
    if version.major >= 3 and version.minor >= 7:
        print(f"  ✓ Python {version.major}.{version.minor}.{version.micro}")
        return True
    else:
        print(f"  ✗ Python {version.major}.{version.minor}.{version.micro}")
        print("    Please use Python 3.7 or higher")
        return False

def test_dependencies():
    """Check if required packages are installed."""
    print("\nChecking dependencies...")
    required = [
        'google.auth',
        'google_auth_oauthlib',
        'googleapiclient',
        'anthropic',
        'yaml',
        'dotenv'
    ]

    all_installed = True
    for package in required:
        try:
            __import__(package)
            print(f"  ✓ {package}")
        except ImportError:
            print(f"  ✗ {package} (not installed)")
            all_installed = False

    if not all_installed:
        print("\n  Run: pip install -r requirements.txt")

    return all_installed

def test_config_files():
    """Check if required config files exist."""
    print("\nChecking configuration files...")

    checks = {
        'config.yaml': 'Configuration file',
        '.env': 'Environment variables (copy from .env.example)',
    }

    all_exist = True
    for filename, description in checks.items():
        if os.path.exists(filename):
            print(f"  ✓ {filename}")
        else:
            print(f"  ✗ {filename} - {description}")
            all_exist = False

    return all_exist

def test_credentials():
    """Check if credentials file exists."""
    print("\nChecking Google credentials...")

    if os.path.exists('credentials.json'):
        print("  ✓ credentials.json found")
        return True
    else:
        print("  ✗ credentials.json not found")
        print("    Follow docs/google_sheets_setup.md to set up Google Sheets API")
        return False

def test_api_key():
    """Check if API key is set."""
    print("\nChecking Anthropic API key...")

    if not os.path.exists('.env'):
        print("  ✗ .env file not found")
        return False

    from dotenv import load_dotenv
    load_dotenv()

    api_key = os.getenv('ANTHROPIC_API_KEY')
    if api_key and api_key.startswith('sk-ant-'):
        print("  ✓ ANTHROPIC_API_KEY is set")
        return True
    else:
        print("  ✗ ANTHROPIC_API_KEY not properly set in .env")
        print("    Get your key from: https://console.anthropic.com/")
        return False

def test_config_values():
    """Check if config.yaml has required values."""
    print("\nChecking config.yaml values...")

    try:
        import yaml
        with open('config.yaml', 'r') as f:
            config = yaml.safe_load(f)

        spreadsheet_id = config.get('google_sheets', {}).get('spreadsheet_id', '')

        if spreadsheet_id and len(spreadsheet_id) > 20:
            print("  ✓ spreadsheet_id is set")
            return True
        else:
            print("  ✗ spreadsheet_id not properly configured")
            print("    Update config.yaml with your Google Sheets ID")
            return False
    except Exception as e:
        print(f"  ✗ Error reading config.yaml: {e}")
        return False

def main():
    """Run all tests."""
    print("=" * 60)
    print("WORKOUT PLANNER - SETUP TEST")
    print("=" * 60)

    results = [
        test_python_version(),
        test_dependencies(),
        test_config_files(),
        test_credentials(),
        test_api_key(),
        test_config_values()
    ]

    print("\n" + "=" * 60)
    if all(results):
        print("✓ ALL CHECKS PASSED!")
        print("=" * 60)
        print("\nYou're ready to run the workout planner!")
        print("Run: python main.py")
    else:
        print("✗ SOME CHECKS FAILED")
        print("=" * 60)
        print("\nPlease fix the issues above before running main.py")
        print("See QUICKSTART.md for setup instructions")
    print()

if __name__ == "__main__":
    main()
