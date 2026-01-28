"""
Exercise History page - View detailed history for any exercise
"""

import streamlit as st
from src.ui_utils import render_page_header, get_authenticated_reader
from src.analytics import WorkoutAnalytics


def show():
    """Render the exercise history page"""

    render_page_header("Exercise History", "View detailed progression for any exercise", "📋")

    try:
        # Get authenticated reader
        reader = get_authenticated_reader()

        analytics = WorkoutAnalytics(reader)
        analytics.load_historical_data(weeks_back=12)

        # Get unique exercise list
        all_exercises = set()
        for workout in analytics.historical_data:
            for exercise in workout.get('exercises', []):
                exercise_name = exercise.get('exercise', '').strip()
                if exercise_name:
                    all_exercises.add(exercise_name)

        # Exercise selector
        selected_exercise = st.selectbox(
            "Select an exercise to view history:",
            sorted(all_exercises)
        )

        if selected_exercise:
            st.markdown(f"### 📊 History: {selected_exercise}")

            # Filter workouts for this exercise
            exercise_history = []
            for workout in analytics.historical_data:
                for exercise in workout.get('exercises', []):
                    if exercise.get('exercise', '').strip() == selected_exercise:
                        exercise_history.append({
                            'date': workout.get('date', ''),
                            'sets': exercise.get('sets', ''),
                            'reps': exercise.get('reps', ''),
                            'load': exercise.get('load', ''),
                            'notes': exercise.get('notes', ''),
                            'log': exercise.get('log', '')
                        })

            # Display history table
            if exercise_history:
                st.write(f"**Total sessions logged:** {len(exercise_history)}")

                # Create table
                for i, session in enumerate(reversed(exercise_history)):
                    with st.expander(f"{session['date']} - {session['sets']} x {session['reps']} @ {session['load']}"):
                        st.write(f"**Sets:** {session['sets']}")
                        st.write(f"**Reps:** {session['reps']}")
                        st.write(f"**Load:** {session['load']}")
                        if session['notes']:
                            st.write(f"**Notes:** {session['notes']}")
                        if session['log']:
                            st.write(f"**Logged:** {session['log']}")
            else:
                st.info("No history found for this exercise yet.")

    except Exception as e:
        st.error(f"Unable to load exercise history: {e}")
        st.info("Make sure you have workout data logged in Google Sheets.")

    # Back button
    if st.button("🏠 Back to Dashboard", use_container_width=True):
        st.session_state.current_page = 'dashboard'
        st.rerun()
