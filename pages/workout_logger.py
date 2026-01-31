"""
Workout Logger page - Log today's workout in real-time
"""

import streamlit as st
from datetime import datetime
import html
from src.ui_utils import (
    render_page_header, 
    get_authenticated_reader, 
    action_button, 
    empty_state,
    progress_bar
)
from src.design_system import get_colors


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
            empty_state(
                "📝",
                "No Workout Plan",
                "Generate a plan first, then come back to log your workouts!"
            )
            action_button("Generate Plan Now", "generate", "🚀", accent=True, use_container_width=True)
            return

        # Use the most recent sheet
        current_sheet = all_sheets[-1]
        reader.sheet_name = current_sheet

        # Read the current week's plan
        week_data = reader.read_workout_history()

        if not week_data:
            st.markdown("""
            <div style="text-align:center;padding:2rem;background:#f0f2f6;border-radius:8px;">
                <div style="font-size:3rem;margin-bottom:1rem;">📊</div>
                <div style="font-weight:600;margin-bottom:0.5rem;">Empty Sheet</div>
                <div style="color:#666;">The sheet `{current_sheet}` exists but has no workout data.</div>
            </div>
            """, unsafe_allow_html=True)
            return

        # Find today's workout (case-insensitive)
        todays_workout = None
        for workout in week_data:
            workout_date = workout.get('date', '')
            if day_name.lower() in workout_date.lower():
                todays_workout = workout
                break

        if not todays_workout:
            empty_state(
                "😌",
                "Rest Day",
                f"No workout scheduled for {day_name}. Enjoy your recovery!"
            )
            action_button("Back to Dashboard", "dashboard", "🏠", use_container_width=True)
            return

        # Display today's workout plan
        exercises = todays_workout.get('exercises', [])

        if not exercises:
            st.markdown("""
            <div style="text-align:center;padding:2rem;background:#f0f2f6;border-radius:8px;">
                <div style="font-size:3rem;margin-bottom:1rem;">🤔</div>
                <div style="font-weight:600;margin-bottom:0.5rem;">No Exercises</div>
                <div style="color:#666;">Today's workout is empty - check your plan.</div>
            </div>
            """, unsafe_allow_html=True)
            return

        st.markdown(f"### 🏋️ Today's Workout: {todays_workout.get('date', '')}")
        
        # Show progress bar for completion tracking
        logged_count = sum(1 for ex in exercises if ex.get('log', '').strip())
        if logged_count > 0 or 'workout_logs' in st.session_state:
            session_logged = sum(1 for idx in range(len(exercises)) if st.session_state.get('workout_logs', {}).get(f"log_{idx}", ""))
            total_logged = max(logged_count, session_logged)
            progress_bar(total_logged, len(exercises))
        
        st.markdown("---")

        # Initialize session state for logging
        if 'workout_logs' not in st.session_state:
            st.session_state.workout_logs = {}
        if 'last_save_time' not in st.session_state:
            st.session_state.last_save_time = None

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

        # Sticky save bar for mobile - always visible at bottom
        st.markdown("""
        <style>
        .save-button-container {
            position: sticky;
            bottom: 0;
            background: white;
            padding: 1rem;
            border-top: 2px solid #000;
            z-index: 999;
            margin: 0 -1rem;
        }
        @media (max-width: 768px) {
            .save-button-container {
                position: fixed;
                bottom: 0;
                left: 0;
                right: 0;
                padding: 1rem;
                box-shadow: 0 -2px 10px rgba(0,0,0,0.1);
            }
        }
        </style>
        """, unsafe_allow_html=True)

        # Count how many exercises have logs
        logs_count = sum(1 for idx in range(len(exercises)) if st.session_state.workout_logs.get(f"log_{idx}", ""))
        
        colors = get_colors()

        # Show save status with accent color
        if 'last_save_time' in st.session_state and st.session_state.last_save_time:
            save_time = st.session_state.last_save_time
            st.success(f"✅ Last saved: {save_time} ({logs_count}/{len(exercises)} exercises logged)")
        elif logs_count > 0:
            st.markdown(f"""
            <div style="background: rgba(0, 212, 170, 0.1); border-left: 4px solid {colors['accent']}; padding: 1rem; border-radius: 4px; margin: 1rem 0;">
                📝 <strong>{logs_count}/{len(exercises)} exercises logged</strong> - Don't forget to save!
            </div>
            """, unsafe_allow_html=True)
        else:
            st.info("💡 Enter your workout data above, then click Save to store it in Google Sheets")

        # Save button
        col1, col2, col3 = st.columns([1, 2, 1])

        with col1:
            action_button("Back to Dashboard", "dashboard", "🏠", use_container_width=True)

        with col2:
            save_button_key = "save_workout_main"
            if st.button("💾 Save to Google Sheets", type="primary", use_container_width=True, help="Saves all workout logs to your Google Sheet", key=save_button_key):
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
                    with st.spinner("Saving to Google Sheets..."):
                        success = reader.write_workout_logs(todays_workout.get('date', ''), logs_to_save)

                    if success:
                        # Store save time
                        st.session_state.last_save_time = datetime.now().strftime("%I:%M %p")

                        st.success(f"✅ Saved {logs_count} exercise log{'s' if logs_count != 1 else ''} to Google Sheets!")
                        st.balloons()

                        # Don't clear session state or redirect - let user stay on page
                        st.rerun()
                    else:
                        st.error("❌ Failed to save workout log")
                        st.warning("""
                        **Troubleshooting Steps:**
                        1. Check your internet connection
                        2. Verify Google Sheets is accessible
                        3. Ensure today's workout exists in the sheet
                        4. Try refreshing the page and logging in again
                        """)
                        
                        # Show what was being saved for debugging
                        with st.expander("🔍 Debug: What was being saved"):
                            st.write(f"Date: {todays_workout.get('date', 'Unknown')}")
                            st.write(f"Number of logs: {len(logs_to_save)}")
                            for i, log in enumerate(logs_to_save[:3]):
                                st.write(f"{i+1}. {log['exercise']}: '{log['log'][:50]}'")

                except Exception as e:
                    st.error(f"❌ Error saving workout: {str(e)}")
                    st.warning("""
                    **Troubleshooting Steps:**
                    1. Check your internet connection
                    2. Verify Google Sheets is accessible  
                    3. Try refreshing the page
                    4. Contact support if issue persists
                    """)
                    
                    with st.expander("🔍 Technical Details"):
                        import traceback
                        st.code(traceback.format_exc())

        with col3:
            if st.button("Clear All", use_container_width=True, help="Clear all unsaved logs"):
                st.session_state.workout_logs = {}
                if 'last_save_time' in st.session_state:
                    del st.session_state.last_save_time
                st.rerun()

    except Exception as e:
        st.error(f"Unable to load workout plan: {e}")
        st.info("Make sure you have a workout plan generated in Google Sheets.")

        action_button("Back to Dashboard", "dashboard", "🏠", use_container_width=True)
