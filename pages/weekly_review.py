"""
Weekly Review page - Browse and review past workout weeks
"""

import streamlit as st
from src.ui_utils import render_page_header, get_authenticated_reader, action_button, empty_state
from src.design_system import get_colors
import re
import html


def show():
    """Render the weekly review page"""

    render_page_header("Weekly Review", "Browse your workout history week by week")
    colors = get_colors()

    try:
        # Get authenticated reader
        reader = get_authenticated_reader()

        # Get all weekly plan sheets
        all_sheets = reader.get_all_weekly_plan_sheets()

        if not all_sheets:
            empty_state(
                "",
                "No History Yet",
                "Complete your first week of workouts to see reviews here!"
            )
            action_button("Back to Dashboard", "dashboard", width="stretch")
            return

        # Reverse order so most recent is first
        all_sheets_reversed = list(reversed(all_sheets))

        # Week selector
        st.markdown("### Select a Week")
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
                st.markdown(f"""
                <div style="text-align:center;padding:2rem;background:{colors['background']};border-radius:10px;border:1px solid {colors['border_medium']};">
                    <div style="font-weight:600;margin-bottom:0.5rem;color:{colors['text_primary']};">No Data for This Week</div>
                    <div style="color:{colors['text_secondary']};">This week exists but has no workout entries yet.</div>
                </div>
                """.strip(), unsafe_allow_html=True)
                return

            # Display week overview
            st.markdown("---")
            week_display = selected_sheet.replace('(Weekly Plan) ', '').replace('Weekly Plan (', '').replace(')', '')
            st.markdown(f"## Week of {week_display}")

            # Calculate week metrics
            completed_days = len([w for w in week_data if any(ex.get('log', '').strip() for ex in w.get('exercises', []))])
            total_days = len(week_data)
            total_exercises = sum(len(w.get('exercises', [])) for w in week_data)

            # Calculate total volume
            total_volume = 0
            total_sets = 0
            for workout in week_data:
                for exercise in workout.get('exercises', []):
                    sets_str = exercise.get('sets', '')
                    reps_str = exercise.get('reps', '')
                    load_str = exercise.get('load', '')

                    sets_match = re.search(r'(\d+)', sets_str)
                    reps_match = re.search(r'(\d+)', reps_str)
                    load_match = re.search(r'([\d\.]+)', load_str)

                    if sets_match:
                        total_sets += int(sets_match.group(1))

                    if sets_match and reps_match and load_match:
                        sets = int(sets_match.group(1))
                        reps = int(reps_match.group(1))
                        load = float(load_match.group(1))
                        total_volume += sets * reps * load

            # Add link to Google Sheets
            sheet_url = f"https://docs.google.com/spreadsheets/d/{reader.spreadsheet_id}/edit#gid=0"
            st.markdown(f"""
            <a href="{sheet_url}" target="_blank" style="
                display: inline-block;
                padding: 0.5rem 1rem;
                background: {colors['info']};
                color: #FFFFFF;
                text-decoration: none;
                border-radius: 10px;
                font-weight: 500;
                margin-bottom: 1rem;
            ">Open in Google Sheets</a>
            """.strip(), unsafe_allow_html=True)
            
            st.markdown("---")

            # Display summary metrics
            col1, col2, col3, col4 = st.columns(4)

            with col1:
                completion_rate = (completed_days / total_days * 100) if total_days > 0 else 0
                st.metric("Days Trained", f"{completed_days} / {total_days}", f"{completion_rate:.0f}%")

            with col2:
                st.metric("Total Exercises", total_exercises)

            with col3:
                st.metric("Total Sets", total_sets)

            with col4:
                st.metric("Total Volume", f"{int(total_volume):,} kg")

            # Week-over-week comparison (if previous week exists)
            if len(all_sheets) > 1:
                current_index = all_sheets.index(selected_sheet)
                if current_index > 0:
                    # Get previous week data
                    prev_sheet = all_sheets[current_index - 1]
                    reader.sheet_name = prev_sheet
                    prev_week_data = reader.read_workout_history()

                    # Calculate previous week volume
                    prev_volume = 0
                    for workout in prev_week_data:
                        for exercise in workout.get('exercises', []):
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
                                prev_volume += sets * reps * load

                    # Show comparison
                    volume_change = total_volume - prev_volume
                    volume_change_pct = (volume_change / prev_volume * 100) if prev_volume > 0 else 0

                    st.markdown("---")
                    st.markdown("### Week-over-Week Comparison")

                    col1, col2, col3 = st.columns(3)

                    with col1:
                        st.metric(
                            "Volume Change",
                            f"{int(total_volume):,} kg",
                            f"{'+' if volume_change >= 0 else ''}{int(volume_change):,} kg ({volume_change_pct:+.1f}%)"
                        )

                    with col2:
                        prev_completed = len([w for w in prev_week_data if any(ex.get('log', '').strip() for ex in w.get('exercises', []))])
                        completion_change = completed_days - prev_completed
                        st.metric(
                            "Days Trained",
                            f"{completed_days}",
                            f"{'+' if completion_change >= 0 else ''}{completion_change}"
                        )

                    with col3:
                        # Calculate consistency streak
                        if completion_rate >= 80:
                            st.metric("Completion Rate", f"{completion_rate:.0f}%", "On track")
                        else:
                            st.metric("Completion Rate", f"{completion_rate:.0f}%", "Room to improve")

            st.markdown("---")

            # Display each day
            days_of_week = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']

            st.markdown("### Day-by-Day Breakdown")

            for workout in week_data:
                workout_date = workout.get('date', 'Unknown')
                exercises = workout.get('exercises', [])

                # Try to extract day of week from date string
                day_name = None
                for day in days_of_week:
                    if day in workout_date:
                        day_name = day
                        break

                # Check if workout was completed
                has_logs = any(ex.get('log', '').strip() for ex in exercises)
                completion_status = "Completed" if has_logs else "Planned"
                status_color = colors['success'] if has_logs else colors['warning']
                
                # Create expandable section with enhanced styling
                expander_label = f"**{workout_date}**"
                with st.expander(expander_label, expanded=False):
                    # Show status badge at top
                    st.markdown(f"""
                    <div style="
                        display: inline-block;
                        padding: 0.5rem 1rem;
                        background: {status_color}15;
                        border-left: 4px solid {status_color};
                        border-radius: 10px;
                        margin-bottom: 1rem;
                        font-weight: 600;
                        color: {status_color};
                    ">
                        {completion_status}
                    </div>
                    """.strip(), unsafe_allow_html=True)
                    if not exercises:
                        st.markdown(f"""
                        <div style="text-align:center;padding:1.5rem;background:{colors['background']};border-radius:10px;border:1px solid {colors['border_medium']};">
                            <div style="color:{colors['text_secondary']};">Rest day - no exercises planned</div>
                        </div>
                        """.strip(), unsafe_allow_html=True)
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
                            rest = ex.get('rest', '')
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
                            if rest:
                                info_parts.append(f"Rest: {rest}")

                            info_str = " x ".join(info_parts) if info_parts else ""
                            safe_exercise_name = html.escape(exercise_name)
                            safe_info_str = html.escape(info_str)
                            safe_log = html.escape(log)
                            safe_notes = html.escape(notes)

                            # Display exercise with styling
                            if log:
                                # Completed exercise - show with checkmark
                                st.markdown(f"""
                                <div style="background-color: rgba(52, 199, 89, 0.12); padding: 0.75rem; border-left: 3px solid {colors['success']}; margin-bottom: 0.5rem; border-radius: 10px;">
                                    <div style="font-weight: 600; color: {colors['text_primary']};">{safe_exercise_name}</div>
                                    <div style="font-size: 0.9rem; color: {colors['text_secondary']};">{safe_info_str}</div>
                                    <div style="font-size: 0.85rem; color: {colors['text_secondary']}; margin-top: 0.25rem;">
                                        <strong>Logged:</strong> {safe_log}
                                    </div>
                                </div>
                                """.strip(), unsafe_allow_html=True)
                            else:
                                # Planned but not completed
                                st.markdown(f"""
                                <div style="background-color: {colors['background']}; padding: 0.75rem; border-left: 3px solid {colors['border_medium']}; margin-bottom: 0.5rem; border-radius: 10px;">
                                    <div style="font-weight: 600; color: {colors['text_primary']};">{safe_exercise_name}</div>
                                    <div style="font-size: 0.9rem; color: {colors['text_secondary']};">{safe_info_str}</div>
                                    {f'<div style="font-size: 0.85rem; color: {colors["text_secondary"]}; margin-top: 0.25rem;"><em>{safe_notes}</em></div>' if notes else ''}
                                </div>
                                """.strip(), unsafe_allow_html=True)

                        st.markdown("<br>", unsafe_allow_html=True)

            st.markdown("---")

            # Quick stats for the week
            st.markdown("### Week Highlights")

            # Find heaviest lifts and best performances
            heaviest_lifts = {}

            for workout in week_data:
                for exercise in workout.get('exercises', []):
                    exercise_name = exercise.get('exercise', '').lower()
                    load_str = exercise.get('load', '')

                    load_match = re.search(r'([\d\.]+)', load_str)
                    if load_match:
                        load = float(load_match.group(1))

                        # Track main lifts
                        if 'squat' in exercise_name and 'back' in exercise_name:
                            if 'Back Squat' not in heaviest_lifts or load > heaviest_lifts['Back Squat']:
                                heaviest_lifts['Back Squat'] = load
                        elif 'bench' in exercise_name and 'press' in exercise_name:
                            if 'Bench Press' not in heaviest_lifts or load > heaviest_lifts['Bench Press']:
                                heaviest_lifts['Bench Press'] = load
                        elif 'deadlift' in exercise_name:
                            if 'Deadlift' not in heaviest_lifts or load > heaviest_lifts['Deadlift']:
                                heaviest_lifts['Deadlift'] = load

            if heaviest_lifts:
                cols = st.columns(len(heaviest_lifts))
                for i, (lift, weight) in enumerate(heaviest_lifts.items()):
                    with cols[i]:
                        st.metric(f"Top {lift}", f"{weight} kg")
            else:
                st.markdown("""
                <div style="text-align:center;padding:2rem;color:var(--color-text-secondary);">
                    <div>No main lift PRs this week - keep pushing!</div>
                </div>
                """.strip())

    except Exception as e:
        st.error(f"Unable to load workout history: {e}")
        st.info("Make sure you have workout data logged in Google Sheets.")
        import traceback
        with st.expander("Error details"):
            st.code(traceback.format_exc())

    # Navigation buttons
    st.markdown("---")
    col1, col2 = st.columns(2)
    with col1:
        action_button("Back to Dashboard", "dashboard", width="stretch")
    with col2:
        action_button("View Progress", "progress", width="stretch")
