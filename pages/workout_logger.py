"""
Workout Logger page - Log today's workout in real-time
"""

import streamlit as st
import yaml
from datetime import datetime
from src.sheets_reader import SheetsReader


def show():
    """Render the workout logger page"""

    st.markdown('<div class="main-header">📝 Log Workout</div>', unsafe_allow_html=True)

    # Get today's date
    today = datetime.now()
    day_name = today.strftime("%A")
    date_str = today.strftime("%B %d, %Y")

    st.markdown(f'<div class="sub-header">{day_name}, {date_str}</div>', unsafe_allow_html=True)

    try:
        # Load config and authenticate
        with open('config.yaml', 'r') as f:
            config = yaml.safe_load(f)

        reader = SheetsReader(
            credentials_file=config['google_sheets']['credentials_file'],
            spreadsheet_id=config['google_sheets']['spreadsheet_id']
        )
        reader.authenticate()

        # Get the most recent weekly plan sheet
        all_sheets = reader.get_all_weekly_plan_sheets()

        if not all_sheets:
            st.warning("⚠️ No workout plan found. Generate your first plan to start logging!")
            if st.button("🚀 Generate Plan Now", type="primary"):
                st.session_state.current_page = 'generate'
                st.rerun()
            return

        # Use the most recent sheet
        current_sheet = all_sheets[-1]
        reader.sheet_name = current_sheet

        # Debug info - displayed prominently to diagnose cloud issues
        st.info(f"🔧 **Debug Info:** Found {len(all_sheets)} weekly plan sheets")
        st.write(f"**Current sheet:** `{current_sheet}`")
        st.write(f"**All sheets:** {all_sheets}")
        st.markdown("---")

        # Read the current week's plan
        week_data = reader.read_workout_history()

        if not week_data:
            st.warning(f"No workout data found in sheet: `{current_sheet}`")
            st.info("This usually means the sheet exists but has no workout data, or the sheet format is different than expected.")
            return

        # Find today's workout (case-insensitive)
        todays_workout = None
        for workout in week_data:
            workout_date = workout.get('date', '')
            if day_name.lower() in workout_date.lower():
                todays_workout = workout
                break

        if not todays_workout:
            st.info(f"No workout scheduled for {day_name}. Enjoy your rest day!")
            if st.button("🏠 Back to Dashboard", use_container_width=True):
                st.session_state.current_page = 'dashboard'
                st.rerun()
            return

        # Display today's workout plan
        exercises = todays_workout.get('exercises', [])

        if not exercises:
            st.info("No exercises found for today.")
            return

        st.markdown(f"### 🏋️ Today's Workout: {todays_workout.get('date', '')}")
        st.markdown("---")

        # Initialize session state for logging
        if 'workout_logs' not in st.session_state:
            st.session_state.workout_logs = {}

        # Group exercises by block
        blocks = {}
        for i, exercise in enumerate(exercises):
            block = exercise.get('block', 'Other')
            if block not in blocks:
                blocks[block] = []
            blocks[block].append((i, exercise))

        # Display each block with logging inputs
        for block_name, block_exercises in blocks.items():
            if block_name and block_name != 'Other':
                st.markdown(f"### {block_name}")

            for idx, ex in block_exercises:
                exercise_name = ex.get('exercise', 'Unknown Exercise')
                sets = ex.get('sets', '')
                reps = ex.get('reps', '')
                load = ex.get('load', '')
                notes = ex.get('notes', '')
                existing_log = ex.get('log', '')

                # Create a card for each exercise
                with st.container():
                    col1, col2 = st.columns([3, 2])

                    with col1:
                        # Exercise details
                        st.markdown(f"**{exercise_name}**")
                        info_parts = []
                        if sets:
                            info_parts.append(f"{sets} sets")
                        if reps:
                            info_parts.append(f"{reps} reps")
                        if load:
                            info_parts.append(f"@ {load}")

                        if info_parts:
                            st.markdown(f"<span style='color: #666; font-size: 0.9rem;'>{'  ×  '.join(info_parts)}</span>", unsafe_allow_html=True)

                        if notes:
                            st.markdown(f"<span style='color: #888; font-size: 0.85rem; font-style: italic;'>💡 {notes}</span>", unsafe_allow_html=True)

                    with col2:
                        # Logging input
                        log_key = f"log_{idx}"

                        # Show existing log if present
                        if existing_log:
                            st.markdown(f"<div style='background-color: #d4edda; padding: 0.5rem; border-radius: 4px; margin-top: 0.5rem;'><span style='color: #155724; font-size: 0.9rem;'>✅ Logged: {existing_log}</span></div>", unsafe_allow_html=True)
                        else:
                            # Detect exercise type for smart placeholder
                            exercise_lower = exercise_name.lower()
                            is_cardio = any(word in exercise_lower for word in ['walk', 'run', 'bike', 'row', 'ski', 'swim'])

                            if is_cardio:
                                placeholder = "e.g., 10 min @ 3.4mph @ 6% or Done"
                                help_text = "Log duration, speed, incline OR just 'Done' if completed as prescribed"
                            else:
                                placeholder = "e.g., 12,12,11,10 @ 7kg or 12,12,11,10"
                                help_text = "Log reps per set @ weight OR just reps (e.g., 12,12,11,10)"

                            # Input for new log
                            default_value = st.session_state.workout_logs.get(log_key, "")
                            log_input = st.text_input(
                                "Log performance",
                                value=default_value,
                                placeholder=placeholder,
                                key=f"input_{log_key}",
                                help=help_text
                            )

                            # Store in session state
                            if log_input:
                                st.session_state.workout_logs[log_key] = log_input

                st.markdown("<br>", unsafe_allow_html=True)

        st.markdown("---")

        # Save button
        col1, col2, col3 = st.columns([1, 2, 1])

        with col2:
            if st.button("💾 Save Workout Log", type="primary", use_container_width=True):
                # Prepare log data to write back to sheets
                logs_to_save = []

                for idx, ex in enumerate(exercises):
                    log_key = f"log_{idx}"
                    log_value = st.session_state.workout_logs.get(log_key, "")

                    logs_to_save.append({
                        'exercise': ex.get('exercise', ''),
                        'log': log_value
                    })

                # Write logs to Google Sheets
                try:
                    success = reader.write_workout_logs(todays_workout.get('date', ''), logs_to_save)

                    if success:
                        st.success("✅ Workout logged successfully!")
                        st.balloons()

                        # Clear session state
                        st.session_state.workout_logs = {}

                        # Wait a moment then redirect to dashboard
                        import time
                        time.sleep(2)
                        st.session_state.current_page = 'dashboard'
                        st.rerun()
                    else:
                        st.error("Failed to save workout log. Please try again.")

                except Exception as e:
                    st.error(f"Error saving workout: {e}")

        # Cancel button
        with col1:
            if st.button("🏠 Back to Dashboard", use_container_width=True):
                st.session_state.current_page = 'dashboard'
                st.rerun()

    except Exception as e:
        st.error(f"Unable to load workout plan: {e}")
        st.info("Make sure you have a workout plan generated in Google Sheets.")

        if st.button("🏠 Back to Dashboard", use_container_width=True):
            st.session_state.current_page = 'dashboard'
            st.rerun()
