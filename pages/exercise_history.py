"""
Exercise History page - View detailed history for any exercise
"""

import streamlit as st
import pandas as pd
import re
from src.ui_utils import render_page_header, get_authenticated_reader, action_button, empty_state
from src.analytics import WorkoutAnalytics
from src.design_system import get_colors


RPE_PATTERN = re.compile(r"\brpe\s*[:=]?\s*(\d+(?:\.\d+)?)\b", re.IGNORECASE)


def extract_rpe_value(*fields):
    """Parse first valid RPE value from provided text fields."""
    for field in fields:
        text = (field or "").strip()
        if not text:
            continue
        match = RPE_PATTERN.search(text)
        if not match:
            continue
        value = float(match.group(1))
        if 1.0 <= value <= 10.0:
            return value
    return None


def show():
    """Render the exercise history page"""

    render_page_header("Exercise History", "View detailed progression for any exercise")

    try:
        # Get authenticated reader
        reader = get_authenticated_reader()

        analytics = WorkoutAnalytics(reader)
        analytics.load_historical_data(weeks_back=16)

        if not analytics.historical_data:
            empty_state(
                "",
                "No Exercise History",
                "Log your workouts to track progress on individual exercises!"
            )
            action_button("Back to Dashboard", "dashboard", width="stretch")
            return

        # Get unique exercise list
        all_exercises = set()
        for workout in analytics.historical_data:
            for exercise in workout.get('exercises', []):
                exercise_name = exercise.get('exercise', '').strip()
                if exercise_name and exercise_name.lower() != 'exercise':
                    all_exercises.add(exercise_name)

        if not all_exercises:
            empty_state(
                "",
                "No Exercises Found",
                "Your workout history doesn't contain any exercise data yet."
            )
            action_button("Back to Dashboard", "dashboard", width="stretch")
            return

        # Search/Filter UI with improved styling
        st.markdown("### Search Exercises")
        
        colors = get_colors()
        
        st.markdown(f"""
        <div style="
            background: {colors['surface']};
            border: 1px solid {colors['border_medium']};
            border-radius: 10px;
            padding: 1rem;
            margin-bottom: 1.5rem;
        ">
            <div style="font-weight: 600; margin-bottom: 0.5rem;">Quick Tip</div>
            <div style="color: {colors['text_secondary']}; font-size: 0.9rem;">
                Search for any exercise to see your progression over time. Track weights, reps, and performance trends.
            </div>
        </div>
        """.strip(), unsafe_allow_html=True)

        col1, col2 = st.columns([3, 1])

        with col1:
            search_query = st.text_input(
                "Search exercise name:", 
                placeholder="e.g., bench press, curl, squat",
                help="Type any part of the exercise name"
            )

        with col2:
            weeks_filter = st.selectbox(
                "Time Range", 
                [4, 8, 12, 16], 
                index=2,
                help="How many weeks of history to load"
            )

        # Filter exercises based on search
        filtered_exercises = sorted(all_exercises)
        if search_query:
            search_lower = search_query.lower()
            filtered_exercises = [ex for ex in filtered_exercises if search_lower in ex.lower()]

        st.markdown(f"""
        <div style="padding: 0.5rem 0; font-size: 0.9rem; color: {colors['text_secondary']};">
            Found <strong style="color: {colors['accent']};">{len(filtered_exercises)}</strong> exercise(s) in your history
        </div>
        """.strip(), unsafe_allow_html=True)

        if not filtered_exercises:
            st.markdown(f"""
            <div style="text-align:center;padding:2rem;color:{colors['text_secondary']};">
                <div style="font-weight:600;margin-bottom:0.5rem;">No Matches Found</div>
                <div style="font-size:0.9rem;">Try a different search term</div>
            </div>
            """.strip(), unsafe_allow_html=True)
            return

        # Exercise selector
        selected_exercise = st.selectbox(
            "Select an exercise to view history:",
            filtered_exercises
        )

        if selected_exercise:
            st.markdown("---")
            st.markdown(f"## {selected_exercise}")

            # Filter workouts for this exercise (respecting time filter)
            filtered_data = analytics.historical_data[-(weeks_filter * 7):] if len(analytics.historical_data) > weeks_filter * 7 else analytics.historical_data

            exercise_history = []
            for workout in filtered_data:
                for exercise in workout.get('exercises', []):
                    rpe_value = extract_rpe_value(exercise.get('log', ''), exercise.get('notes', ''))
                    if exercise.get('exercise', '').strip() == selected_exercise:
                        exercise_history.append({
                            'date': workout.get('date', ''),
                            'sets': exercise.get('sets', ''),
                            'reps': exercise.get('reps', ''),
                            'load': exercise.get('load', ''),
                            'rest': exercise.get('rest', ''),
                            'rpe': rpe_value,
                            'notes': exercise.get('notes', ''),
                            'log': exercise.get('log', '')
                        })

            # Display history
            if not exercise_history:
                st.markdown(f"""
                <div style="text-align:center;padding:2rem;color:{colors['text_secondary']};">
                    <div style="font-weight:600;margin-bottom:0.5rem;">No History for {selected_exercise}</div>
                    <div style="font-size:0.9rem;">No records found in the last {weeks_filter} weeks</div>
                </div>
                """.strip(), unsafe_allow_html=True)
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
                rpe_values = [session['rpe'] for session in exercise_history if session.get('rpe') is not None]
                if rpe_values:
                    avg_rpe = sum(rpe_values) / len(rpe_values)
                    st.metric("Avg RPE", f"{avg_rpe:.1f}/10")
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
                    st.markdown("### Load Progression")
                    df = pd.DataFrame(chart_data)
                    st.line_chart(df.set_index('Session'))
            except Exception as e:
                pass  # Skip chart if data doesn't support it

            st.markdown("---")

            # Session-by-session breakdown
            st.markdown("### Session History")

            for i, session in enumerate(reversed(exercise_history)):
                # Build summary line
                summary_parts = []
                if session['sets']:
                    summary_parts.append(f"{session['sets']} sets")
                if session['reps']:
                    summary_parts.append(f"{session['reps']} reps")
                if session['load']:
                    summary_parts.append(f"@ {session['load']}")

                summary = " x ".join(summary_parts) if summary_parts else "No data"

                with st.expander(f"**{len(exercise_history) - i}.** {session['date']} - {summary}"):
                    col1, col2 = st.columns(2)

                    with col1:
                        st.markdown("**Prescribed:**")
                        st.write(f"Sets: {session['sets'] or 'N/A'}")
                        st.write(f"Reps: {session['reps'] or 'N/A'}")
                        st.write(f"Load: {session['load'] or 'N/A'}")
                        st.write(f"Rest: {session['rest'] or 'N/A'}")
                        if session['rpe'] is not None:
                            st.write(f"RPE: {session['rpe']:.1f}")

                    with col2:
                        st.markdown("**Logged Performance:**")
                        if session['log']:
                            st.success(f"{session['log']}")
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
    action_button("Back to Dashboard", "dashboard", width="stretch")
