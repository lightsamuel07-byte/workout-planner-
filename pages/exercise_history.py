"""
Exercise History page - View detailed history for any exercise
"""

import streamlit as st
import pandas as pd
import re
from src.ui_utils import render_page_header, get_authenticated_reader, nav_button
from src.analytics import WorkoutAnalytics


def show():
    """Render the exercise history page"""

    render_page_header("Exercise History", "View detailed progression for any exercise", "📋")

    try:
        # Get authenticated reader
        reader = get_authenticated_reader()

        analytics = WorkoutAnalytics(reader)
        analytics.load_historical_data(weeks_back=16)

        if not analytics.historical_data:
            st.warning("No workout history found. Start logging workouts to see exercise history!")
            nav_button("Back to Dashboard", "dashboard", "🏠", use_container_width=True)
            return

        # Get unique exercise list
        all_exercises = set()
        for workout in analytics.historical_data:
            for exercise in workout.get('exercises', []):
                exercise_name = exercise.get('exercise', '').strip()
                if exercise_name and exercise_name.lower() != 'exercise':
                    all_exercises.add(exercise_name)

        if not all_exercises:
            st.info("No exercises found in workout history.")
            nav_button("Back to Dashboard", "dashboard", "🏠", use_container_width=True)
            return

        # Search/Filter UI
        st.markdown("### 🔍 Search Exercises")

        col1, col2 = st.columns([3, 1])

        with col1:
            search_query = st.text_input("Search exercise name:", placeholder="e.g., bench press, curl, squat")

        with col2:
            weeks_filter = st.selectbox("Time Range", [4, 8, 12, 16], index=2)

        # Filter exercises based on search
        filtered_exercises = sorted(all_exercises)
        if search_query:
            search_lower = search_query.lower()
            filtered_exercises = [ex for ex in filtered_exercises if search_lower in ex.lower()]

        st.markdown(f"**Found {len(filtered_exercises)} exercise(s)**")

        if not filtered_exercises:
            st.info("No exercises match your search. Try a different query.")
            return

        # Exercise selector
        selected_exercise = st.selectbox(
            "Select an exercise to view history:",
            filtered_exercises
        )

        if selected_exercise:
            st.markdown("---")
            st.markdown(f"## 📊 {selected_exercise}")

            # Filter workouts for this exercise (respecting time filter)
            filtered_data = analytics.historical_data[-(weeks_filter * 7):] if len(analytics.historical_data) > weeks_filter * 7 else analytics.historical_data

            exercise_history = []
            for workout in filtered_data:
                for exercise in workout.get('exercises', []):
                    if exercise.get('exercise', '').strip() == selected_exercise:
                        exercise_history.append({
                            'date': workout.get('date', ''),
                            'sets': exercise.get('sets', ''),
                            'reps': exercise.get('reps', ''),
                            'load': exercise.get('load', ''),
                            'rest': exercise.get('rest', ''),
                            'rpe': exercise.get('rpe', ''),
                            'notes': exercise.get('notes', ''),
                            'log': exercise.get('log', '')
                        })

            # Display history
            if not exercise_history:
                st.info(f"No history found for '{selected_exercise}' in the last {weeks_filter} weeks.")
                return

            # Summary metrics
            col1, col2, col3 = st.columns(3)

            with col1:
                st.metric("Total Sessions", len(exercise_history))

            with col2:
                # Calculate volume trend (if possible)
                try:
                    loads = []
                    for session in exercise_history:
                        load_str = session['load']
                        load_match = re.search(r'([\d\.]+)', load_str)
                        if load_match:
                            loads.append(float(load_match.group(1)))

                    if len(loads) >= 2:
                        volume_change = loads[-1] - loads[0]
                        st.metric("Load Progression", f"{loads[-1]} kg", f"+{volume_change:.1f} kg" if volume_change >= 0 else f"{volume_change:.1f} kg")
                    else:
                        st.metric("Load Progression", "N/A")
                except Exception:
                    st.metric("Load Progression", "N/A")

            with col3:
                # Average RPE (if tracked)
                rpe_values = [session['rpe'] for session in exercise_history if session.get('rpe')]
                if rpe_values:
                    try:
                        rpe_nums = [float(re.search(r'(\d+)', rpe).group(1)) for rpe in rpe_values if re.search(r'(\d+)', rpe)]
                        if rpe_nums:
                            avg_rpe = sum(rpe_nums) / len(rpe_nums)
                            st.metric("Avg RPE", f"{avg_rpe:.1f}/10")
                        else:
                            st.metric("Avg RPE", "N/A")
                    except Exception:
                        st.metric("Avg RPE", "N/A")
                else:
                    st.metric("Avg RPE", "Not tracked")

            st.markdown("---")

            # Load progression chart (if applicable)
            try:
                chart_data = []
                for i, session in enumerate(exercise_history):
                    load_str = session['load']
                    load_match = re.search(r'([\d\.]+)', load_str)
                    if load_match:
                        chart_data.append({
                            'Session': i + 1,
                            'Load (kg)': float(load_match.group(1))
                        })

                if len(chart_data) >= 2:
                    st.markdown("### 📈 Load Progression")
                    df = pd.DataFrame(chart_data)
                    st.line_chart(df.set_index('Session'))
            except Exception as e:
                pass  # Skip chart if data doesn't support it

            st.markdown("---")

            # Session-by-session breakdown
            st.markdown("### 📝 Session History")

            for i, session in enumerate(reversed(exercise_history)):
                # Build summary line
                summary_parts = []
                if session['sets']:
                    summary_parts.append(f"{session['sets']} sets")
                if session['reps']:
                    summary_parts.append(f"{session['reps']} reps")
                if session['load']:
                    summary_parts.append(f"@ {session['load']}")

                summary = " × ".join(summary_parts) if summary_parts else "No data"

                with st.expander(f"**{len(exercise_history) - i}.** {session['date']} — {summary}"):
                    col1, col2 = st.columns(2)

                    with col1:
                        st.markdown("**Prescribed:**")
                        st.write(f"Sets: {session['sets'] or 'N/A'}")
                        st.write(f"Reps: {session['reps'] or 'N/A'}")
                        st.write(f"Load: {session['load'] or 'N/A'}")
                        st.write(f"Rest: {session['rest'] or 'N/A'}")
                        if session['rpe']:
                            st.write(f"RPE: {session['rpe']}")

                    with col2:
                        st.markdown("**Logged Performance:**")
                        if session['log']:
                            st.success(f"✅ {session['log']}")
                        else:
                            st.info("Not logged")

                        if session['notes']:
                            st.markdown(f"**Notes:** {session['notes']}")

    except Exception as e:
        st.error(f"Unable to load exercise history: {e}")
        st.info("Make sure you have workout data logged in Google Sheets.")
        import traceback
        with st.expander("Error details"):
            st.code(traceback.format_exc())

    st.markdown("---")

    # Back button
    nav_button("Back to Dashboard", "dashboard", "🏠", use_container_width=True)
