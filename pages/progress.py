"""
Progress page - View training progress and stats
"""

import streamlit as st
from datetime import datetime, timedelta

def show():
    """Render the progress page"""

    st.markdown('<div class="main-header">📈 Progress Dashboard</div>', unsafe_allow_html=True)
    st.markdown('<div class="sub-header">Track your strength gains and training progress</div>', unsafe_allow_html=True)

    # Mock data for demonstration
    st.markdown("### 📊 Main Lifts Progress (Last 8 Weeks)")

    # Create sample data using lists of tuples to avoid numpy import
    try:
        import pandas as pd

        chart_data = pd.DataFrame({
            'Week': list(range(1, 9)),
            'Back Squat': [122, 124.5, 125, 127, 127, 129, 129, 131.5],
            'Bench Press': [90, 91, 92, 92.5, 93, 93.5, 94, 96.5],
            'Deadlift': [160, 162, 163, 165, 165, 166, 168, 170.5]
        })

        st.line_chart(chart_data.set_index('Week'))
    except ImportError:
        # Fallback if pandas/numpy has issues
        st.info("Charts temporarily unavailable. Progress metrics shown below.")

    # Progress metrics
    col1, col2, col3 = st.columns(3)

    with col1:
        st.metric(
            "Back Squat",
            "131.5 kg",
            "+9.5 kg (7.8%)",
            delta_color="normal"
        )

    with col2:
        st.metric(
            "Bench Press",
            "96.5 kg",
            "+6.5 kg (7.2%)",
            delta_color="normal"
        )

    with col3:
        st.metric(
            "Deadlift",
            "170.5 kg",
            "+10.5 kg (6.6%)",
            delta_color="normal"
        )

    st.markdown("---")

    # Volume tracking
    st.markdown("### 💪 Weekly Volume Tracking")

    try:
        import pandas as pd

        volume_data = pd.DataFrame({
            'Week': list(range(1, 9)),
            'Total Volume (kg)': [32000, 35000, 37500, 38000, 40000, 41500, 42000, 44200]
        })

        st.bar_chart(volume_data.set_index('Week'))
    except ImportError:
        st.info("Volume chart temporarily unavailable.")

    col1, col2, col3 = st.columns(3)
    with col1:
        st.metric("Current Week", "44,200 kg")
    with col2:
        st.metric("Average", "41,350 kg")
    with col3:
        st.metric("Peak Week", "46,800 kg")

    st.markdown("---")

    # Body focus progress
    st.markdown("### 🎯 Muscle Group Focus Progress")

    col1, col2 = st.columns(2)

    with col1:
        st.markdown("""
        **Volume Increases (Last 8 Weeks)**
        - 💪 Arms: +18% volume
        - 🔥 Medial Delts: +15% volume
        - 📈 Upper Chest: +12% volume
        - 💪 Back Detail: +10% volume
        """)

    with col2:
        st.markdown("""
        **Bicep Grip Rotation Tracking**
        - ✅ 24-week consistency streak
        - ✅ Perfect rotation compliance
        - ✅ Volume within 10-12 set target
        - ✅ 48hr recovery between long-length stimulus
        """)

    st.markdown("---")

    # Achievements
    st.markdown("### 🏆 Achievements")

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
            <div style="padding: 1rem; background-color: #f0f2f6; border-radius: 0.5rem; text-align: center; min-height: 120px;">
                <div style="font-size: 2rem; margin-bottom: 0.5rem;">{emoji}</div>
                <div style="font-weight: bold; margin-bottom: 0.25rem;">{title}</div>
                <div style="font-size: 0.8rem; color: #666;">{desc}</div>
            </div>
            """, unsafe_allow_html=True)

    st.markdown("---")

    # Coming soon features
    st.info("""
    🚧 **Coming Soon:**
    - Body composition photo tracking
    - Detailed exercise history
    - Volume per muscle group charts
    - Injury risk indicators
    - Export to PDF reports
    """)

    # Back button
    if st.button("🏠 Back to Dashboard", use_container_width=True):
        st.session_state.current_page = 'dashboard'
        st.rerun()
