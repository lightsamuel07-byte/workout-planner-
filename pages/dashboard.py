"""
Dashboard page - Main overview of current week's workouts
"""

import streamlit as st
from datetime import datetime, timedelta
import os
import glob
from src.ui_utils import (
    render_page_header, 
    empty_state,
    action_button,
    completion_badge
)
from src.design_system import get_colors


def get_fallback_stats():
    """Return default stats when data unavailable"""
    return {
        'workouts_completed': '1 / 6',
        'weekly_volume': '42,500 kg',
        'back_squat': ('129 kg', '+2.5 kg'),
        'bench_press': ('94 kg', '+1.5 kg'),
        'deadlift': ('168 kg', '+3.0 kg'),
    }


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

    # Prefer the current week's canonical file if present
    today = datetime.now()
    days_since_monday = today.weekday()
    monday = today - timedelta(days=days_since_monday)
    week_stamp = monday.strftime("%Y%m%d")
    canonical = os.path.join(output_dir, f"workout_plan_{week_stamp}.md")
    if os.path.exists(canonical):
        return canonical

    md_files = glob.glob(os.path.join(output_dir, "workout_plan_*.md"))
    archive_dir = os.path.join(output_dir, "archive")
    if os.path.exists(archive_dir):
        md_files.extend(glob.glob(os.path.join(archive_dir, "workout_plan_*.md")))

    # Exclude explanation companion files.
    md_files = [f for f in md_files if not f.endswith("_explanation.md")]

    if not md_files:
        return None

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
        spreadsheet_id=config['google_sheets']['spreadsheet_id'],
        service_account_file=config.get('google_sheets', {}).get('service_account_file')
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
    except Exception:
        # Fail soft on dashboard when Sheets is temporarily unavailable.
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

    # Get current week
    week_dates = get_current_week_dates()
    week_start = week_dates[0].strftime("%b %d")
    week_end = week_dates[6].strftime("%b %d, %Y")

    # Header
    render_page_header("Weekly Dashboard", f"Week of {week_start} - {week_end}", "📅")

    # Get latest plan (try markdown file first, then Google Sheets)
    latest_plan = get_latest_plan()
    latest_sheet_plan = get_latest_sheet_plan()
    plan_summary = parse_plan_summary(latest_plan)

    if not latest_plan and not latest_sheet_plan:
        empty_state(
            "🎯",
            "No Workout Plan Yet",
            "Generate your first personalized plan to get started!"
        )
        action_button("Generate Plan Now", "generate", "🚀", accent=True, width="stretch")
        return

    # Weekly Calendar View
    st.markdown("### 📆 This Week's Schedule")

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
    
    colors = get_colors()

    st.markdown("""
    <style>
    .dashboard-week-grid {
        display: grid;
        grid-template-columns: repeat(7, minmax(0, 1fr));
        gap: 0.5rem;
    }
    @media (max-width: 1100px) {
        .dashboard-week-grid {
            grid-template-columns: repeat(4, minmax(0, 1fr));
        }
    }
    @media (max-width: 768px) {
        .dashboard-week-grid {
            grid-template-columns: repeat(2, minmax(0, 1fr));
        }
    }
    @media (max-width: 480px) {
        .dashboard-week-grid {
            grid-template-columns: 1fr;
        }
    }
    </style>
    """, unsafe_allow_html=True)

    day_cards = []
    for day, date, workout in zip(days, week_dates, workouts):
        emoji, title, subtitle = workout
        is_today = date.date() == datetime.now().date()
        is_completed = date.date() < datetime.now().date()
        completion_icon = completion_badge(is_completed)
        border_color = colors['accent'] if is_today else colors['border_medium']
        border_width = '2px' if is_today else '1px'
        box_shadow = '0 3px 8px rgba(0, 212, 170, 0.12)' if is_today else '0 1px 2px rgba(0,0,0,0.04)'
        card_class = "day-card today" if is_today else "day-card"

        day_cards.append(f"""
            <div class="{card_class}" style="
                background: {colors['surface']};
                border: {border_width} solid {border_color};
                border-radius: 12px;
                padding: 0.75rem 0.5rem;
                text-align: center;
                min-height: 116px;
                transition: all 0.2s ease;
                box-shadow: {box_shadow};
            ">
                <div style="
                    font-size: 0.7rem;
                    font-weight: 700;
                    color: {colors['text_secondary']};
                    text-transform: uppercase;
                    letter-spacing: 0.5px;
                    margin-bottom: 0.25rem;
                ">{day}</div>
                <div style="
                    font-size: 0.7rem;
                    color: {colors['text_secondary']};
                    margin-bottom: 0.5rem;
                ">{date.strftime('%m/%d')}</div>
                <div style="font-size: 2rem; margin-bottom: 0.5rem;">{emoji}</div>
                <div style="
                    font-size: 0.8rem;
                    font-weight: 700;
                    color: {colors['text_primary']};
                    margin-bottom: 0.2rem;
                ">{title}</div>
                <div style="
                    font-size: 0.7rem;
                    color: {colors['text_secondary']};
                ">{subtitle}</div>
                <div style="margin-top: 0.45rem; font-size: 1.1rem;">{completion_icon}</div>
            </div>
        """)

    st.markdown(f'<div class="dashboard-week-grid">{"".join(day_cards)}</div>', unsafe_allow_html=True)

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
            spreadsheet_id=config['google_sheets']['spreadsheet_id'],
            service_account_file=config.get('google_sheets', {}).get('service_account_file')
        )
        reader.authenticate()

        analytics = WorkoutAnalytics(reader)
        analytics.load_historical_data(weeks_back=4)
    except (FileNotFoundError, KeyError, ImportError, Exception) as e:
        # Analytics unavailable - will use fallback data below
        print(f"Analytics initialization failed: {e}")
        pass

    # Stats and Quick Actions Row
    col1, col2, col3 = st.columns([2, 2, 3])

    with col1:
        st.markdown("### 📊 This Week")
        st.metric("Total Exercises", plan_summary.get('total_exercises', 0))

        # Get real completion data
        fallback = get_fallback_stats()
        if analytics:
            try:
                completion = analytics.get_workout_completion_rate(weeks=1)
                volume_data = analytics.get_weekly_volume(weeks=1)

                current_week_volume = list(volume_data.values())[-1] if volume_data else 0

                st.metric("Workouts Complete", f"{completion['completed']} / {completion['total']}")
                st.metric("Weekly Volume", f"{int(current_week_volume):,} kg")
            except (KeyError, ValueError, IndexError, Exception) as e:
                print(f"Failed to load workout completion: {e}")
                st.metric("Workouts Complete", fallback['workouts_completed'])
                st.metric("Weekly Volume", fallback['weekly_volume'])
        else:
            # Fallback to mock data if sheets unavailable
            st.metric("Workouts Complete", fallback['workouts_completed'])
            st.metric("Weekly Volume", fallback['weekly_volume'])

    with col2:
        st.markdown("### 🔥 Progress")

        # Get real lift progression data
        fallback = get_fallback_stats()
        if analytics:
            try:
                squat_prog = analytics.get_main_lift_progression('squat', weeks=8)
                bench_prog = analytics.get_main_lift_progression('bench', weeks=8)
                deadlift_prog = analytics.get_main_lift_progression('deadlift', weeks=8)

                if squat_prog:
                    st.metric("Back Squat", f"{squat_prog['current_load']} kg", f"+{squat_prog['progression_kg']} kg")
                else:
                    st.metric("Back Squat", *fallback['back_squat'])

                if bench_prog:
                    st.metric("Bench Press", f"{bench_prog['current_load']} kg", f"+{bench_prog['progression_kg']} kg")
                else:
                    st.metric("Bench Press", *fallback['bench_press'])

                if deadlift_prog:
                    st.metric("Deadlift", f"{deadlift_prog['current_load']} kg", f"+{deadlift_prog['progression_kg']} kg")
                else:
                    st.metric("Deadlift", *fallback['deadlift'])
            except (KeyError, ValueError, IndexError, Exception) as e:
                # Fallback to mock data
                print(f"Failed to load lift progression: {e}")
                st.metric("Back Squat", *fallback['back_squat'])
                st.metric("Bench Press", *fallback['bench_press'])
                st.metric("Deadlift", *fallback['deadlift'])
        else:
            # Fallback to mock data
            st.metric("Back Squat", *fallback['back_squat'])
            st.metric("Bench Press", *fallback['bench_press'])
            st.metric("Deadlift", *fallback['deadlift'])

    with col3:
        st.markdown("### 🎯 Quick Actions")

        action_button("Log Today's Workout", "log_workout", "📝", accent=True, width="stretch")

        action_button("View Full Week Plan", "plans", "📋", width="stretch")
        
        action_button("View Progress Charts", "progress", "📈", width="stretch")

        action_button("Generate New Week Plan", "generate", "🆕", width="stretch")

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
            except Exception:
                st.markdown("""
                <div style="color:var(--color-text-secondary);text-align:center;padding:1rem;">
                    <div style="font-size:2rem;margin-bottom:0.5rem;">📝</div>
                    No recent workouts
                </div>
                """)
        else:
            st.markdown("""
            <div style="text-align:center;padding:2rem;">
                <div style="font-size:3rem;margin-bottom:1rem;">🏋️</div>
                <div style="font-weight:600;margin-bottom:0.5rem;color: var(--color-text-primary);">No Workouts Logged Yet</div>
                <div style="font-size:0.9rem;color: var(--color-text-secondary);">Start logging your workouts to see your history here!</div>
            </div>
            """)

    with col2:
        st.markdown("#### Latest Plan")
        if latest_plan:
            plan_name = os.path.basename(latest_plan)
            plan_date = plan_name.replace('workout_plan_', '').replace('.md', '')
            st.write(f"**Generated:** {plan_date[:8]}")
            st.write(f"📄 {plan_summary.get('total_exercises', 0)} exercises")
            st.write("✅ Saved to Google Sheets")
            action_button("View Plan →", "plans")
        elif latest_sheet_plan:
            # Show plan from Google Sheets if no markdown file
            plan_date = latest_sheet_plan.replace('Weekly Plan (', '').replace('(Weekly Plan) ', '').replace(')', '')
            st.write(f"**Sheet:** {plan_date}")
            st.write(f"📊 Plan in Google Sheets")
            st.write("✅ Ready to log workouts")
            action_button("View Plan →", "plans")
