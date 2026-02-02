"""
Progress page - View training progress and stats
"""

import streamlit as st
from datetime import datetime, timedelta
from src.ui_utils import render_page_header, get_authenticated_reader, action_button, empty_state
from src.design_system import get_colors

def show():
    """Render the progress page"""

    render_page_header("Progress Dashboard", "Track your strength gains and training progress", "📈")
    
    colors = get_colors()
    
    # Info card
    st.markdown(f"""
    <div style="
        background: {colors['surface']};
        border: 2px solid {colors['border_light']};
        border-left: 4px solid {colors['accent']};
        border-radius: 8px;
        padding: 1rem;
        margin-bottom: 2rem;
    ">
        <div style="font-weight: 600; margin-bottom: 0.5rem;">📊 Progress Tracking</div>
        <div style="color: {colors['text_secondary']}; font-size: 0.9rem;">
            See your strength progression on the main compound lifts over the last 8 weeks. Keep logging your workouts to track improvements!
        </div>
    </div>
    """, unsafe_allow_html=True)

    st.markdown("### 🏋️ Main Lifts Progress (Last 8 Weeks)")

    analytics = None  # Initialize to None to avoid NameError later

    try:
        import pandas as pd
        from src.analytics import WorkoutAnalytics

        # Get authenticated reader
        reader = get_authenticated_reader()

        # Load analytics
        analytics = WorkoutAnalytics(reader)
        analytics.load_historical_data(weeks_back=8)

        # Get progression data
        squat_prog = analytics.get_main_lift_progression('squat', weeks=8)
        bench_prog = analytics.get_main_lift_progression('bench', weeks=8)
        deadlift_prog = analytics.get_main_lift_progression('deadlift', weeks=8)

        # Show current metrics for each lift that has data
        has_any_data = squat_prog or bench_prog or deadlift_prog
        
        if has_any_data:
            col1, col2, col3 = st.columns(3)

            with col1:
                if squat_prog:
                    st.metric(
                        "Back Squat",
                        f"{squat_prog['current_load']} kg",
                        f"+{squat_prog['progression_kg']} kg ({squat_prog['progression_pct']}%)"
                    )
                else:
                    st.metric("Back Squat", "No data", "")

            with col2:
                if bench_prog:
                    st.metric(
                        "Bench Press",
                        f"{bench_prog['current_load']} kg",
                        f"+{bench_prog['progression_kg']} kg ({bench_prog['progression_pct']}%)"
                    )
                else:
                    st.metric("Bench Press", "No data", "")

            with col3:
                if deadlift_prog:
                    st.metric(
                        "Deadlift",
                        f"{deadlift_prog['current_load']} kg",
                        f"+{deadlift_prog['progression_kg']} kg ({deadlift_prog['progression_pct']}%)"
                    )
                else:
                    st.metric("Deadlift", "No data", "")
        else:
            empty_state(
                "📈",
                "Not Enough Data",
                "Keep logging workouts to see your progress trends!"
            )

    except Exception as e:
        st.error(f"Unable to load progress data: {e}")
        st.info("Charts temporarily unavailable. Continue logging workouts in Google Sheets.")

    st.markdown("---")

    # Volume tracking
    st.markdown("### 💪 Weekly Volume Tracking")

    try:
        if not analytics:
            raise Exception("Analytics not initialized")

        volume_data = analytics.get_weekly_volume(weeks=8)

        if volume_data:
            weeks = sorted(volume_data.keys())

            volume_df = pd.DataFrame({
                'Week': list(range(1, len(weeks) + 1)),
                'Total Volume (kg)': [volume_data[w] for w in weeks]
            })

            st.bar_chart(volume_df.set_index('Week'))

            # Calculate stats
            volumes = list(volume_data.values())
            current_volume = volumes[-1]
            avg_volume = sum(volumes) / len(volumes)
            peak_volume = max(volumes)

            col1, col2, col3 = st.columns(3)
            with col1:
                st.metric("Current Week", f"{int(current_volume):,} kg")
            with col2:
                st.metric("Average", f"{int(avg_volume):,} kg")
            with col3:
                st.metric("Peak Week", f"{int(peak_volume):,} kg")
        else:
            st.markdown("""
            <div style="text-align:center;padding:2rem;">
                <div style="font-size:3rem;margin-bottom:1rem;">💪</div>
                <div style="font-weight:600;margin-bottom:0.5rem;color: var(--color-text-primary);">No Volume Data</div>
                <div style="font-size:0.9rem;color: var(--color-text-secondary);">Log more workouts to see volume trends</div>
            </div>
            """, unsafe_allow_html=True)

    except Exception as e:
        st.error(f"Unable to load volume data: {e}")

    st.markdown("---")

    # Body focus progress
    st.markdown("### 🎯 Muscle Group Focus Progress")

    col1, col2 = st.columns(2)

    with col1:
        st.markdown("**Volume Increases (Last 8 Weeks)**")

        try:
            if not analytics:
                raise Exception("Analytics not initialized")

            focus_groups = ['arms', 'shoulders', 'chest', 'back']

            for group in focus_groups:
                group_volume = analytics.get_muscle_group_volume(group, weeks=8)

                if group_volume and len(group_volume) >= 2:
                    volumes = list(group_volume.values())
                    first_week = volumes[0]
                    last_week = volumes[-1]
                    
                    emoji = {'arms': '💪', 'shoulders': '🔥', 'chest': '📈', 'back': '💪'}.get(group, '✅')
                    if first_week > 0:
                        pct_increase = ((last_week - first_week) / first_week) * 100
                        st.write(f"{emoji} {group.title()}: +{pct_increase:.0f}% volume")
                    else:
                        st.write(f"{emoji} {group.title()}: {last_week:.0f} kg volume")
                else:
                    st.write(f"✅ {group.title()}: insufficient data")

        except Exception as e:
            st.write("Unable to calculate muscle group progress")

    with col2:
        st.markdown("**Bicep Grip Rotation Tracking**")

        try:
            if not analytics:
                raise Exception("Analytics not initialized")

            bicep_compliance = analytics.get_bicep_grip_rotation_compliance(weeks=4)

            if bicep_compliance['compliant']:
                st.write("✅ Perfect rotation compliance")
                st.write(f"✅ {bicep_compliance['total_bicep_sessions']} sessions tracked")
            else:
                st.write(f"⚠️ {len(bicep_compliance['violations'])} violations")
                for violation in bicep_compliance['violations']:
                    st.write(f"- {violation}")

        except Exception as e:
            st.write("Unable to check grip rotation compliance")

    st.markdown("---")

    # Achievements
    st.markdown("### 🏆 Achievements")
    
    colors = get_colors()

    achievements = [
        ("🥇", "8-Week Consistency Streak", "Never missed a scheduled workout"),
        ("💪", "Squat +20kg Milestone", "Added 20kg to back squat in 12 weeks"),
        ("📈", "12 Consecutive PRs", "Set personal records 12 sessions in a row"),
        ("🎯", "Perfect Programming", "24 weeks of optimal bicep grip rotation"),
    ]

    cols = st.columns(4)
    for col, (emoji, title, desc) in zip(cols, achievements):
        with col:
            st.markdown(f"""
            <div style="
                padding: 1rem; 
                background-color: {colors['surface']}; 
                border: 2px solid {colors['border_light']};
                border-radius: 8px; 
                text-align: center; 
                min-height: 120px;
                transition: all 150ms cubic-bezier(0.4, 0, 0.2, 1);
            " class="metric-card">
                <div style="font-size: 2rem; margin-bottom: 0.5rem;">{emoji}</div>
                <div style="font-weight: bold; margin-bottom: 0.25rem; color: {colors['text_primary']};">{title}</div>
                <div style="font-size: 0.8rem; color: {colors['text_secondary']};">{desc}</div>
            </div>
            """, unsafe_allow_html=True)

    st.markdown("---")

    # Back button
    action_button("Back to Dashboard", "dashboard", "🏠", use_container_width=True)
