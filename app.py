#!/usr/bin/env python3
"""
Workout Planning App - Streamlit Web Interface
Main entry point for the web application.
"""

import streamlit as st
import os
from datetime import datetime, timedelta

# Configure the page
st.set_page_config(
    page_title="💪 Samuel's Workout Planner",
    page_icon="💪",
    layout="wide",
    initial_sidebar_state="expanded"
)

# Password Protection
def check_password():
    """Returns True if the user has entered the correct password."""

    def password_entered():
        """Checks whether a password entered by the user is correct."""
        # Try to get password from secrets, fall back to default for local dev
        try:
            correct_password = st.secrets.get("APP_PASSWORD", "workout2026")
        except:
            correct_password = "workout2026"

        if st.session_state["password"] == correct_password:
            st.session_state["password_correct"] = True
            del st.session_state["password"]  # Don't store password
        else:
            st.session_state["password_correct"] = False

    if "password_correct" not in st.session_state:
        # First run, show password input
        st.markdown("## 🔒 Authentication Required")
        st.text_input(
            "Enter password to access the app:",
            type="password",
            on_change=password_entered,
            key="password"
        )
        st.markdown("*This app is password-protected for authorized users only.*")
        return False
    elif not st.session_state["password_correct"]:
        # Password incorrect, show input again
        st.markdown("## 🔒 Authentication Required")
        st.text_input(
            "Enter password to access the app:",
            type="password",
            on_change=password_entered,
            key="password"
        )
        st.error("😕 Password incorrect. Please try again.")
        return False
    else:
        # Password correct
        return True

if not check_password():
    st.stop()

# Minimal CSS - Only Fix Critical Issues
st.markdown("""
    <style>
    /* Fix text area overlapping labels */
    .stTextArea label[data-testid="stWidgetLabel"] {
        display: none;
    }

    /* Clean corners */
    button, input, textarea, select {
        border-radius: 0 !important;
    }
    </style>
""", unsafe_allow_html=True)

# Initialize session state
if 'current_page' not in st.session_state:
    st.session_state.current_page = 'dashboard'

# Sidebar navigation
with st.sidebar:
    st.markdown("# 💪 Workout Planner")
    st.markdown("*Powered by Claude AI*")
    st.markdown("---")

    if st.button("📊 Dashboard", use_container_width=True, key="nav_dashboard"):
        st.session_state.current_page = 'dashboard'
        st.rerun()

    if st.button("📝 Log Workout", use_container_width=True, key="nav_log_workout"):
        st.session_state.current_page = 'log_workout'
        st.rerun()

    if st.button("🆕 Generate Plan", use_container_width=True, key="nav_generate"):
        st.session_state.current_page = 'generate'
        st.rerun()

    if st.button("📋 View Plans", use_container_width=True, key="nav_plans"):
        st.session_state.current_page = 'plans'
        st.rerun()

    if st.button("📈 Progress", use_container_width=True, key="nav_progress"):
        st.session_state.current_page = 'progress'
        st.rerun()

    if st.button("📅 Weekly Review", use_container_width=True, key="nav_weekly_review"):
        st.session_state.current_page = 'weekly_review'
        st.rerun()

    if st.button("📋 Exercise History", use_container_width=True, key="nav_exercise_history"):
        st.session_state.current_page = 'exercise_history'
        st.rerun()

    st.markdown("---")
    st.markdown("### ⚙️ Quick Settings")
    st.markdown(f"**User:** Samuel")
    st.markdown(f"**Goal:** Strength + Aesthetics")

    # 1RM Settings
    st.markdown("---")
    st.markdown("### 🏋️ Current 1RMs")

    # Initialize session state for 1RMs if not exists
    if 'back_squat_1rm' not in st.session_state:
        st.session_state.back_squat_1rm = 129.0
    if 'bench_press_1rm' not in st.session_state:
        st.session_state.bench_press_1rm = 96.5
    if 'deadlift_1rm' not in st.session_state:
        st.session_state.deadlift_1rm = 168.0

    st.session_state.back_squat_1rm = st.number_input(
        "Back Squat (kg)",
        value=st.session_state.back_squat_1rm,
        step=0.5,
        key="input_back_squat"
    )
    st.session_state.bench_press_1rm = st.number_input(
        "Bench Press (kg)",
        value=st.session_state.bench_press_1rm,
        step=0.5,
        key="input_bench_press"
    )
    st.session_state.deadlift_1rm = st.number_input(
        "Deadlift (kg)",
        value=st.session_state.deadlift_1rm,
        step=0.5,
        key="input_deadlift"
    )

    # Google Sheets link
    st.markdown("---")
    st.markdown("### 📊 Google Sheets")
    sheets_url = "https://docs.google.com/spreadsheets/d/1S9Bh_f69Hgy4iqgtqT9F-t1CR6eiN9e6xJecyHyDBYU"
    st.markdown(f"[Open Workout Log]({sheets_url})")

# Main content area - route to different pages
if st.session_state.current_page == 'dashboard':
    from pages import dashboard
    dashboard.show()
elif st.session_state.current_page == 'generate':
    from pages import generate_plan
    generate_plan.show()
elif st.session_state.current_page == 'plans':
    from pages import view_plans
    view_plans.show()
elif st.session_state.current_page == 'progress':
    from pages import progress
    progress.show()
elif st.session_state.current_page == 'weekly_review':
    from pages import weekly_review
    weekly_review.show()
elif st.session_state.current_page == 'exercise_history':
    from pages import exercise_history
    exercise_history.show()
elif st.session_state.current_page == 'log_workout':
    from pages import workout_logger
    workout_logger.show()
