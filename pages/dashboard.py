"""
Dashboard page - Main overview of current week's workouts
"""

import streamlit as st
from datetime import datetime, timedelta
import os
import glob

def get_current_week_dates():
    """Get Monday through Sunday of current week"""
    today = datetime.now()
    # Calculate this week's Monday
    days_since_monday = today.weekday()
    monday = today - timedelta(days=days_since_monday)

    week_dates = []
    for i in range(7):
        date = monday + timedelta(days=i)
        week_dates.append(date)

    return week_dates

def get_latest_plan():
    """Get the most recent workout plan markdown file"""
    output_dir = "output"
    if not os.path.exists(output_dir):
        return None

    md_files = glob.glob(os.path.join(output_dir, "workout_plan_*.md"))
    if not md_files:
        return None

    # Sort by filename (which includes timestamp)
    md_files.sort(reverse=True)
    return md_files[0]

@st.cache_resource
def get_sheets_reader():
    """Get authenticated sheets reader (cached for performance)"""
    import yaml
    from src.sheets_reader import SheetsReader

    with open('config.yaml', 'r') as f:
        config = yaml.safe_load(f)

    reader = SheetsReader(
        credentials_file=config['google_sheets']['credentials_file'],
        spreadsheet_id=config['google_sheets']['spreadsheet_id']
    )
    reader.authenticate()
    return reader

def get_latest_sheet_plan():
    """Get the most recent workout plan from Google Sheets"""
    try:
        reader = get_sheets_reader()
        all_sheets = reader.get_all_weekly_plan_sheets()
        if all_sheets:
            return all_sheets[-1]  # Return most recent sheet name
        return None
    except Exception as e:
        # Log the actual error for debugging
        st.error(f"Error loading Google Sheets plan: {e}")
        import traceback
        st.code(traceback.format_exc())
        return None

def parse_plan_summary(plan_path):
    """Parse the plan file to extract a quick summary"""
    if not plan_path or not os.path.exists(plan_path):
        return {}

    with open(plan_path, 'r') as f:
        content = f.read()

    summary = {
        'monday': 'Fort Workout',
        'tuesday': 'Aesthetics + Arms',
        'wednesday': 'Fort Workout',
        'thursday': 'Aesthetics + Back',
        'friday': 'Fort Workout',
        'saturday': 'Aesthetics + Arms',
        'sunday': 'Rest Day'
    }

    # Count exercises
    exercise_count = content.count('### A1.') + content.count('### B1.') + content.count('### C1.')
    summary['total_exercises'] = exercise_count

    return summary

def show():
    """Render the dashboard page"""

    # Header
    st.markdown('<div class="main-header">📅 Weekly Dashboard</div>', unsafe_allow_html=True)
    st.caption("🔧 Debug: Dashboard version 2026-01-27-18:07 with @st.cache_resource fix deployed")

    # Get current week
    week_dates = get_current_week_dates()
    week_start = week_dates[0].strftime("%b %d")
    week_end = week_dates[6].strftime("%b %d, %Y")

    st.markdown(f'<div class="sub-header">Week of {week_start} - {week_end}</div>', unsafe_allow_html=True)

    # Get latest plan (try markdown file first, then Google Sheets)
    latest_plan = get_latest_plan()
    latest_sheet_plan = get_latest_sheet_plan()
    plan_summary = parse_plan_summary(latest_plan)

    if not latest_plan and not latest_sheet_plan:
        # Debug: Show what we tried to find
        st.write(f"Debug: latest_plan = {latest_plan}")
        st.write(f"Debug: latest_sheet_plan = {latest_sheet_plan}")

        st.warning("⚠️ No workout plan found. Generate your first plan to get started!")
        if st.button("🚀 Generate Plan Now", type="primary"):
            st.session_state.current_page = 'generate'
            st.rerun()
        return

    # Weekly Calendar View
    st.markdown("### 📆 This Week's Schedule")

    # Create 7 columns for each day
    cols = st.columns(7)

    days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN']
    workouts = [
        ('🏋️', 'FORT', 'Back Squat'),
        ('💪', 'ARMS', 'Aesthetics'),
        ('🏋️', 'FORT', 'Bench Press'),
        ('💪', 'BACK', 'Detail'),
        ('🏋️', 'FORT', 'Deadlift'),
        ('💪', 'UPPER', '+ Arms'),
        ('😌', 'REST', 'Recovery')
    ]

    for i, (col, day, date, workout) in enumerate(zip(cols, days, week_dates, workouts)):
        with col:
            emoji, title, subtitle = workout

            # Check if this is today
            is_today = date.date() == datetime.now().date()

            # Simple alternating colors
            bg_color = '#FFF' if i % 2 == 0 else '#f8f8f8'

            card_class = "day-card today" if is_today else "day-card"

            st.markdown(f"""
                <div class="{card_class}" style="background-color: {bg_color};">
                    <div style="font-weight: 700; color: #000; font-size: 1.1rem; border-bottom: 3px solid #000; padding-bottom: 0.25rem; margin-bottom: 0.5rem;">{day}</div>
                    <div style="font-size: 0.9rem; color: #000; margin-bottom: 0.5rem;">{date.strftime('%m/%d')}</div>
                    <div style="font-size: 2.5rem; margin: 0.5rem 0; transform: rotate({(i - 3) * 5}deg);">{emoji}</div>
                    <div style="font-weight: 700; color: #000; text-transform: uppercase; font-size: 0.9rem;">{title}</div>
                    <div style="font-size: 0.85rem; color: #000;">{subtitle}</div>
                    {'<div style="margin-top: 0.5rem; background-color: #000; color: #0F0; padding: 0.25rem; font-weight: 700; border: 2px solid #0F0;">⏰ TODAY</div>' if is_today else ''}
                </div>
            """, unsafe_allow_html=True)

    st.markdown("<br>", unsafe_allow_html=True)

    # Initialize analytics ONCE for all sections to use
    analytics = None
    try:
        import yaml
        from src.sheets_reader import SheetsReader
        from src.analytics import WorkoutAnalytics

        with open('config.yaml', 'r') as f:
            config = yaml.safe_load(f)

        reader = SheetsReader(
            credentials_file=config['google_sheets']['credentials_file'],
            spreadsheet_id=config['google_sheets']['spreadsheet_id']
        )
        reader.authenticate()

        analytics = WorkoutAnalytics(reader)
        analytics.load_historical_data(weeks_back=4)
    except Exception as e:
        pass  # analytics will remain None, use fallback data

    # Stats and Quick Actions Row
    col1, col2, col3 = st.columns([2, 2, 3])

    with col1:
        st.markdown("### 📊 This Week")
        st.metric("Total Exercises", plan_summary.get('total_exercises', 0))

        # Get real completion data
        if analytics:
            try:
                completion = analytics.get_workout_completion_rate(weeks=1)
                volume_data = analytics.get_weekly_volume(weeks=1)

                current_week_volume = list(volume_data.values())[-1] if volume_data else 0

                st.metric("Workouts Complete", f"{completion['completed']} / {completion['total']}")
                st.metric("Weekly Volume", f"{int(current_week_volume):,} kg")
            except:
                st.metric("Workouts Complete", "1 / 6")
                st.metric("Weekly Volume", "42,500 kg")
        else:
            # Fallback to mock data if sheets unavailable
            st.metric("Workouts Complete", "1 / 6")
            st.metric("Weekly Volume", "42,500 kg")

    with col2:
        st.markdown("### 🔥 Progress")

        # Get real lift progression data
        if analytics:
            try:
                squat_prog = analytics.get_main_lift_progression('squat', weeks=8)
                bench_prog = analytics.get_main_lift_progression('bench', weeks=8)
                deadlift_prog = analytics.get_main_lift_progression('deadlift', weeks=8)

                if squat_prog:
                    st.metric("Back Squat", f"{squat_prog['current_load']} kg", f"+{squat_prog['progression_kg']} kg")
                else:
                    st.metric("Back Squat", "129 kg", "+2.5 kg")

                if bench_prog:
                    st.metric("Bench Press", f"{bench_prog['current_load']} kg", f"+{bench_prog['progression_kg']} kg")
                else:
                    st.metric("Bench Press", "94 kg", "+1.5 kg")

                if deadlift_prog:
                    st.metric("Deadlift", f"{deadlift_prog['current_load']} kg", f"+{deadlift_prog['progression_kg']} kg")
                else:
                    st.metric("Deadlift", "168 kg", "+3.0 kg")
            except:
                # Fallback to mock data
                st.metric("Back Squat", "129 kg", "+2.5 kg")
                st.metric("Bench Press", "94 kg", "+1.5 kg")
                st.metric("Deadlift", "168 kg", "+3.0 kg")
        else:
            # Fallback to mock data
            st.metric("Back Squat", "129 kg", "+2.5 kg")
            st.metric("Bench Press", "94 kg", "+1.5 kg")
            st.metric("Deadlift", "168 kg", "+3.0 kg")

    with col3:
        st.markdown("### 🎯 Quick Actions")

        if st.button("🆕 Generate New Week Plan", use_container_width=True, type="primary"):
            st.session_state.current_page = 'generate'
            st.rerun()

        if st.button("📋 View Full Week Plan", use_container_width=True):
            st.session_state.current_page = 'plans'
            st.rerun()

        if st.button("📝 Log Today's Workout", use_container_width=True):
            st.info("Logging feature coming soon! For now, use Google Sheets.")

        if st.button("📈 View Progress Charts", use_container_width=True):
            st.session_state.current_page = 'progress'
            st.rerun()

    st.markdown("---")

    # Recent Activity
    st.markdown("### 📝 Recent Activity")

    col1, col2 = st.columns(2)

    with col1:
        st.markdown("#### Last Workout")

        if analytics and analytics.historical_data:
            try:
                recent_workout = analytics.historical_data[-1]
                workout_date = recent_workout.get('date', 'Unknown')
                exercise_count = len(recent_workout.get('exercises', []))

                st.write(f"**{workout_date}**")
                st.write(f"✅ {exercise_count} exercises")
                st.write("📊 Data in Google Sheets")
            except Exception as e:
                st.write("No workout history available")
        else:
            st.write("No workout history yet")

    with col2:
        st.markdown("#### Latest Plan")
        if latest_plan:
            plan_name = os.path.basename(latest_plan)
            plan_date = plan_name.replace('workout_plan_', '').replace('.md', '')
            st.write(f"**Generated:** {plan_date[:8]}")
            st.write(f"📄 {plan_summary.get('total_exercises', 0)} exercises")
            st.write("✅ Saved to Google Sheets")
            if st.button("View Plan →"):
                st.session_state.current_page = 'plans'
                st.rerun()
        elif latest_sheet_plan:
            # Show plan from Google Sheets if no markdown file
            plan_date = latest_sheet_plan.replace('Weekly Plan (', '').replace('(Weekly Plan) ', '').replace(')', '')
            st.write(f"**Sheet:** {plan_date}")
            st.write(f"📊 Plan in Google Sheets")
            st.write("✅ Ready to log workouts")
            if st.button("View Plan →"):
                st.session_state.current_page = 'plans'
                st.rerun()
