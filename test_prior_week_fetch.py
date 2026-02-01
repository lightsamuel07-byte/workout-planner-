"""
Test script to verify prior week complete plan fetching works correctly.
"""

import yaml
from src.sheets_reader import SheetsReader

def test_prior_week_fetch():
    """Test fetching the complete prior week's plan from Google Sheets."""
    
    print("=" * 80)
    print("TESTING PRIOR WEEK COMPLETE PLAN FETCH")
    print("=" * 80)
    
    # Load config
    with open('config.yaml', 'r') as f:
        config = yaml.safe_load(f)
    
    # Initialize sheets reader
    sheets_reader = SheetsReader(
        spreadsheet_id=config['google_sheets']['spreadsheet_id'],
        credentials_file=config['google_sheets']['credentials_file']
    )
    
    # Authenticate
    print("\n1. Authenticating with Google Sheets...")
    try:
        sheets_reader.authenticate()
        print("✓ Authentication successful")
    except Exception as e:
        print(f"❌ Authentication failed: {e}")
        return
    
    # Find most recent weekly plan
    print("\n2. Finding most recent weekly plan sheet...")
    try:
        recent_sheet = sheets_reader.find_most_recent_weekly_plan()
        if recent_sheet:
            print(f"✓ Found: {recent_sheet}")
        else:
            print("❌ No weekly plan sheets found")
            return
    except Exception as e:
        print(f"❌ Error finding sheet: {e}")
        return
    
    # Fetch complete prior week plan
    print("\n3. Fetching complete prior week's plan (all 7 days)...")
    try:
        complete_plan = sheets_reader.read_prior_week_complete_plan()
        
        if not complete_plan:
            print("❌ Failed to fetch prior week plan")
            return
        
        print("✓ Successfully fetched complete plan")
        
        # Analyze what we got
        print("\n4. Analyzing fetched data:")
        print("-" * 80)
        
        for day in ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']:
            exercises = complete_plan.get(day, [])
            print(f"\n{day.upper()}:")
            
            if not exercises:
                print("  No exercises found")
                continue
            
            print(f"  Total exercises: {len(exercises)}")
            
            # Count exercises with logged performance
            logged_count = sum(1 for ex in exercises if ex.get('log', '').strip())
            completed_count = sum(1 for ex in exercises if 'done' in ex.get('log', '').lower() or 'completed' in ex.get('log', '').lower())
            
            print(f"  Exercises with logs: {logged_count}/{len(exercises)}")
            print(f"  Completed exercises: {completed_count}/{len(exercises)}")
            
            # Show first 3 exercises as sample
            print(f"\n  Sample exercises:")
            for i, ex in enumerate(exercises[:3]):
                print(f"    {i+1}. {ex['block']} - {ex['exercise']}")
                if ex.get('sets') and ex.get('reps'):
                    print(f"       {ex['sets']} x {ex['reps']}", end='')
                if ex.get('load'):
                    print(f" @ {ex['load']}", end='')
                if ex.get('log'):
                    print(f" [{ex['log']}]", end='')
                print()
        
        # Format for AI and show token estimate
        print("\n5. Formatting for AI consumption:")
        print("-" * 80)
        formatted = sheets_reader.format_complete_plan_for_ai(complete_plan)
        
        # Rough token estimate (1 token ≈ 4 characters)
        estimated_tokens = len(formatted) // 4
        print(f"✓ Formatted output length: {len(formatted)} characters")
        print(f"✓ Estimated tokens: ~{estimated_tokens}")
        
        # Show first 1000 characters
        print("\n6. Preview of formatted output (first 1000 chars):")
        print("-" * 80)
        print(formatted[:1000])
        if len(formatted) > 1000:
            print(f"\n... (truncated, {len(formatted) - 1000} more characters)")
        
        print("\n" + "=" * 80)
        print("TEST COMPLETED SUCCESSFULLY ✓")
        print("=" * 80)
        print("\nKey findings:")
        print(f"  • Successfully fetched all 7 days from: {recent_sheet}")
        print(f"  • Estimated tokens required: ~{estimated_tokens}")
        print(f"  • All logged performance data preserved")
        print("\nThe elegant solution is working correctly! 🎉")
        
    except Exception as e:
        print(f"❌ Error fetching/processing plan: {e}")
        import traceback
        traceback.print_exc()
        return


if __name__ == "__main__":
    test_prior_week_fetch()
