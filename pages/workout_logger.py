"""
Workout Logger page - Log today's workout in real-time
"""

import streamlit as st
from datetime import datetime
import html
from src.ui_utils import render_page_header, get_authenticated_reader, nav_button


def show():
    """Render the workout logger page"""

    # Get today's date
    today = datetime.now()
    day_name = today.strftime("%A")
    date_str = today.strftime("%B %d, %Y")

    render_page_header("Log Workout", f"{day_name}, {date_str}", "📝")

    try:
        # Get authenticated reader
        reader = get_authenticated_reader()

        # Get the most recent weekly plan sheet
        all_sheets = reader.get_all_weekly_plan_sheets()

        if not all_sheets:
            st.warning("⚠️ No workout plan found. Generate your first plan to start logging!")
            nav_button("Generate Plan Now", "generate", "🚀", type="primary")
            return

        # Use the most recent sheet
        current_sheet = all_sheets[-1]
        reader.sheet_name = current_sheet

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
            nav_button("Back to Dashboard", "dashboard", "🏠", use_container_width=True)
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
                st.markdown("---")
                st.markdown(f"### {block_name}")

            for idx, ex in block_exercises:
                exercise_name = ex.get('exercise', 'Unknown Exercise')
                sets = ex.get('sets', '')
                reps = ex.get('reps', '')
                load = ex.get('load', '')
                rest = ex.get('rest', '')
                notes = ex.get('notes', '')
                existing_log = ex.get('log', '')

                # Create a card for each exercise
                with st.container():
                    col1, col2 = st.columns([2, 1])

                    with col1:
                        # Exercise name
                        st.markdown(f"**{exercise_name}**")

                        # 4-column grid for metrics (like view_plans.py)
                        st.markdown(f"""
                        <div style="display: grid; grid-template-columns: repeat(4, 1fr); gap: 0.25rem; margin: 0.5rem 0;">
                            <div style="border: 2px solid #000; padding: 0.5rem; background: #fff;">
                                <div style="font-size: 0.7rem; text-transform: uppercase; font-weight: 700; color: #666;">SETS</div>
                                <div style="font-weight: 700;">{html.escape(sets) if sets else '-'}</div>
                            </div>
                            <div style="border: 2px solid #000; padding: 0.5rem; background: #fff;">
                                <div style="font-size: 0.7rem; text-transform: uppercase; font-weight: 700; color: #666;">REPS</div>
                                <div style="font-weight: 700;">{html.escape(reps) if reps else '-'}</div>
                            </div>
                            <div style="border: 2px solid #000; padding: 0.5rem; background: #fff;">
                                <div style="font-size: 0.7rem; text-transform: uppercase; font-weight: 700; color: #666;">LOAD</div>
                                <div style="font-weight: 700;">{html.escape(load) if load else '-'}</div>
                            </div>
                            <div style="border: 2px solid #000; padding: 0.5rem; background: #fff;">
                                <div style="font-size: 0.7rem; text-transform: uppercase; font-weight: 700; color: #666;">REST</div>
                                <div style="font-weight: 700;">{html.escape(rest) if rest else '-'}</div>
                            </div>
                        </div>
                        """, unsafe_allow_html=True)

                        # Notes below grid
                        if notes:
                            st.markdown(f"<span style='color: #888; font-size: 0.9rem; font-style: italic;'>💡 {html.escape(notes)}</span>", unsafe_allow_html=True)

                    with col2:
                        # Logging input
                        log_key = f"log_{idx}"

                        # Show existing log if present
                        if existing_log:
                            st.markdown(f"<div style='background-color: #d4edda; padding: 0.5rem; border-radius: 4px; margin-top: 0.5rem;'><span style='color: #155724; font-size: 0.9rem;'>✅ Logged: {html.escape(existing_log)}</span></div>", unsafe_allow_html=True)
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
            nav_button("Back to Dashboard", "dashboard", "🏠", use_container_width=True)

    except Exception as e:
        st.error(f"Unable to load workout plan: {e}")
        st.info("Make sure you have a workout plan generated in Google Sheets.")

        nav_button("Back to Dashboard", "dashboard", "🏠", use_container_width=True)
