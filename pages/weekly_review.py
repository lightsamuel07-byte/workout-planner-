"""
Weekly Review page - Browse and review past workout weeks
"""

import streamlit as st
import yaml
from src.sheets_reader import SheetsReader
from datetime import datetime


def show():
    """Render the weekly review page"""

    st.markdown('<div class="main-header">📅 Weekly Review</div>', unsafe_allow_html=True)
    st.markdown('<div class="sub-header">Browse your workout history week by week</div>', unsafe_allow_html=True)

    try:
        # Load config and authenticate
        with open('config.yaml', 'r') as f:
            config = yaml.safe_load(f)

        reader = SheetsReader(
            credentials_file=config['google_sheets']['credentials_file'],
            spreadsheet_id=config['google_sheets']['spreadsheet_id']
        )
        reader.authenticate()

        # Get all weekly plan sheets
        all_sheets = reader.get_all_weekly_plan_sheets()

        if not all_sheets:
            st.warning("⚠️ No workout history found. Generate your first plan to get started!")
            return

        # Reverse order so most recent is first
        all_sheets_reversed = list(reversed(all_sheets))

        # Week selector
        st.markdown("### 📆 Select a Week")
        selected_sheet = st.selectbox(
            "Choose a week to review:",
            all_sheets_reversed,
            format_func=lambda x: f"Week of {x.replace('(Weekly Plan) ', '').replace('Weekly Plan (', '').replace(')', '')}"
        )

        if selected_sheet:
            # Load that week's data
            reader.sheet_name = selected_sheet
            week_data = reader.read_workout_history()

            if not week_data:
                st.info("No workout data found for this week.")
                return

            # Display week overview
            st.markdown("---")
            week_display = selected_sheet.replace('(Weekly Plan) ', '').replace('Weekly Plan (', '').replace(')', '')
            st.markdown(f"## 🗓️ Week of {week_display}")

            # Count workouts completed
            completed_days = len([w for w in week_data if any(ex.get('log', '').strip() for ex in w.get('exercises', []))])
            total_days = len(week_data)

            col1, col2, col3 = st.columns(3)
            with col1:
                st.metric("Days Trained", f"{completed_days} / {total_days}")
            with col2:
                total_exercises = sum(len(w.get('exercises', [])) for w in week_data)
                st.metric("Total Exercises", total_exercises)
            with col3:
                # Calculate total volume
                total_volume = 0
                for workout in week_data:
                    for exercise in workout.get('exercises', []):
                        import re
                        sets_str = exercise.get('sets', '')
                        reps_str = exercise.get('reps', '')
                        load_str = exercise.get('load', '')

                        sets_match = re.search(r'(\d+)', sets_str)
                        reps_match = re.search(r'(\d+)', reps_str)
                        load_match = re.search(r'([\d\.]+)', load_str)

                        if sets_match and reps_match and load_match:
                            sets = int(sets_match.group(1))
                            reps = int(reps_match.group(1))
                            load = float(load_match.group(1))
                            total_volume += sets * reps * load

                st.metric("Total Volume", f"{int(total_volume):,} kg")

            st.markdown("---")

            # Display each day
            days_of_week = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']
            day_emojis = {
                'Monday': '🏋️',
                'Tuesday': '💪',
                'Wednesday': '🏋️',
                'Thursday': '💪',
                'Friday': '🏋️',
                'Saturday': '💪',
                'Sunday': '😌'
            }

            for workout in week_data:
                workout_date = workout.get('date', 'Unknown')
                exercises = workout.get('exercises', [])

                # Try to extract day of week from date string
                day_name = None
                for day in days_of_week:
                    if day in workout_date:
                        day_name = day
                        break

                emoji = day_emojis.get(day_name, '📋') if day_name else '📋'

                # Check if workout was completed
                has_logs = any(ex.get('log', '').strip() for ex in exercises)
                completion_badge = "✅ COMPLETED" if has_logs else "⏸️ Planned"
                badge_color = "#28a745" if has_logs else "#6c757d"

                # Create expandable section for each day
                with st.expander(f"{emoji} **{workout_date}** - {completion_badge}", expanded=False):
                    if not exercises:
                        st.info("No exercises planned for this day")
                        continue

                    # Group exercises by block
                    blocks = {}
                    for exercise in exercises:
                        block = exercise.get('block', 'Other')
                        if block not in blocks:
                            blocks[block] = []
                        blocks[block].append(exercise)

                    # Display each block
                    for block_name, block_exercises in blocks.items():
                        if block_name and block_name != 'Other':
                            st.markdown(f"**{block_name}**")

                        for ex in block_exercises:
                            exercise_name = ex.get('exercise', 'Unknown Exercise')
                            sets = ex.get('sets', '')
                            reps = ex.get('reps', '')
                            load = ex.get('load', '')
                            notes = ex.get('notes', '')
                            log = ex.get('log', '')

                            # Build exercise info string
                            info_parts = []
                            if sets:
                                info_parts.append(f"{sets} sets")
                            if reps:
                                info_parts.append(f"{reps} reps")
                            if load:
                                info_parts.append(f"@ {load}")

                            info_str = " × ".join(info_parts) if info_parts else ""

                            # Display exercise with styling
                            if log:
                                # Completed exercise - show with checkmark
                                st.markdown(f"""
                                <div style="background-color: #d4edda; padding: 0.75rem; border-left: 4px solid #28a745; margin-bottom: 0.5rem; border-radius: 4px;">
                                    <div style="font-weight: 600; color: #155724;">✓ {exercise_name}</div>
                                    <div style="font-size: 0.9rem; color: #155724;">{info_str}</div>
                                    <div style="font-size: 0.85rem; color: #155724; margin-top: 0.25rem;">
                                        <strong>Logged:</strong> {log}
                                    </div>
                                </div>
                                """, unsafe_allow_html=True)
                            else:
                                # Planned but not completed
                                st.markdown(f"""
                                <div style="background-color: #f8f9fa; padding: 0.75rem; border-left: 4px solid #6c757d; margin-bottom: 0.5rem; border-radius: 4px;">
                                    <div style="font-weight: 600; color: #495057;">{exercise_name}</div>
                                    <div style="font-size: 0.9rem; color: #6c757d;">{info_str}</div>
                                    {f'<div style="font-size: 0.85rem; color: #6c757d; margin-top: 0.25rem;"><em>{notes}</em></div>' if notes else ''}
                                </div>
                                """, unsafe_allow_html=True)

                        st.markdown("<br>", unsafe_allow_html=True)

            st.markdown("---")

            # Quick stats for the week
            st.markdown("### 📊 Week Highlights")

            # Find heaviest lifts
            heaviest_lifts = {}
            for workout in week_data:
                for exercise in workout.get('exercises', []):
                    exercise_name = exercise.get('exercise', '').lower()
                    load_str = exercise.get('load', '')

                    import re
                    load_match = re.search(r'([\d\.]+)', load_str)
                    if load_match:
                        load = float(load_match.group(1))

                        # Track main lifts
                        if 'squat' in exercise_name and 'back' in exercise_name:
                            if 'back squat' not in heaviest_lifts or load > heaviest_lifts['back squat']:
                                heaviest_lifts['back squat'] = load
                        elif 'bench' in exercise_name or 'chest press' in exercise_name:
                            if 'bench press' not in heaviest_lifts or load > heaviest_lifts['bench press']:
                                heaviest_lifts['bench press'] = load
                        elif 'deadlift' in exercise_name:
                            if 'deadlift' not in heaviest_lifts or load > heaviest_lifts['deadlift']:
                                heaviest_lifts['deadlift'] = load

            if heaviest_lifts:
                cols = st.columns(len(heaviest_lifts))
                for i, (lift, weight) in enumerate(heaviest_lifts.items()):
                    with cols[i]:
                        st.metric(f"Top {lift.title()}", f"{weight} kg")

    except Exception as e:
        st.error(f"Unable to load workout history: {e}")
        st.info("Make sure you have workout data logged in Google Sheets.")

    # Navigation buttons
    st.markdown("---")
    col1, col2 = st.columns(2)
    with col1:
        if st.button("🏠 Back to Dashboard", use_container_width=True):
            st.session_state.current_page = 'dashboard'
            st.rerun()
    with col2:
        if st.button("📈 View Progress", use_container_width=True):
            st.session_state.current_page = 'progress'
            st.rerun()
