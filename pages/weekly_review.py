"""
Weekly Review page - Browse and review past workout weeks
"""

import streamlit as st
from src.ui_utils import render_page_header, get_authenticated_reader, nav_button
from datetime import datetime
import re


def show():
    """Render the weekly review page"""

    render_page_header("Weekly Review", "Browse your workout history week by week", "📅")

    try:
        # Get authenticated reader
        reader = get_authenticated_reader()

        # Get all weekly plan sheets
        all_sheets = reader.get_all_weekly_plan_sheets()

        if not all_sheets:
            st.markdown("""
            <div style="text-align:center;padding:3rem 2rem;background:#f8f9fa;border-radius:12px;margin:2rem 0;">
                <div style="font-size:4rem;margin-bottom:1rem;">📅</div>
                <div style="font-size:1.25rem;font-weight:600;margin-bottom:0.5rem;">No History Yet</div>
                <div style="color:#666;margin-bottom:1.5rem;">Complete your first week of workouts to see reviews here!</div>
            </div>
            """, unsafe_allow_html=True)
            nav_button("Back to Dashboard", "dashboard", "🏠", use_container_width=True)
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
                st.markdown("""
                <div style="text-align:center;padding:2rem;background:#f0f2f6;border-radius:8px;">
                    <div style="font-size:3rem;margin-bottom:1rem;">📊</div>
                    <div style="font-weight:600;margin-bottom:0.5rem;">No Data for This Week</div>
                    <div style="color:#666;">This week exists but has no workout entries yet.</div>
                </div>
                """, unsafe_allow_html=True)
                return

            # Display week overview
            st.markdown("---")
            week_display = selected_sheet.replace('(Weekly Plan) ', '').replace('Weekly Plan (', '').replace(')', '')
            st.markdown(f"## 🗓️ Week of {week_display}")

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
                    st.markdown("### 📊 Week-over-Week Comparison")

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
                            st.metric("Completion Rate", f"{completion_rate:.0f}%", "✅ On track")
                        else:
                            st.metric("Completion Rate", f"{completion_rate:.0f}%", "⚠️ Room to improve")

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

            st.markdown("### 📅 Day-by-Day Breakdown")

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

                # Create expandable section for each day
                with st.expander(f"{emoji} **{workout_date}** - {completion_badge}", expanded=False):
                    if not exercises:
                        st.markdown("""
                        <div style="text-align:center;padding:1.5rem;background:#f8f9fa;border-radius:8px;">
                            <div style="font-size:2rem;margin-bottom:0.5rem;">😴</div>
                            <div style="color:#666;">Rest day - no exercises planned</div>
                        </div>
                        """, unsafe_allow_html=True)
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
                                info_parts.append(f"• Rest: {rest}")

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
            st.markdown("### 🏆 Week Highlights")

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
                <div style="text-align:center;padding:2rem;color:#888;">
                    <div style="font-size:2rem;margin-bottom:0.5rem;">💪</div>
                    <div>No main lift PRs this week - keep pushing!</div>
                </div>
                """)

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
        nav_button("Back to Dashboard", "dashboard", "🏠", use_container_width=True)
    with col2:
        nav_button("View Progress", "progress", "📈", use_container_width=True)
