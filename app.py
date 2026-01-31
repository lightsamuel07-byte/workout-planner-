#!/usr/bin/env python3
"""
Workout Planning App - Streamlit Web Interface
Main entry point for the web application.
"""

import streamlit as st
import os
import sys
import importlib
from datetime import datetime, timedelta

# Ensure pages directory is in Python path
sys.path.insert(0, os.path.dirname(__file__))

# Import pages using importlib for better Streamlit Cloud compatibility
# Force reload on every run to pick up code changes
try:
    # Import pages package first to ensure it's in sys.modules
    import pages

    dashboard = importlib.import_module('pages.dashboard')
    generate_plan = importlib.import_module('pages.generate_plan')
    view_plans = importlib.import_module('pages.view_plans')
    progress = importlib.import_module('pages.progress')
    weekly_review = importlib.import_module('pages.weekly_review')
    exercise_history = importlib.import_module('pages.exercise_history')
    workout_logger = importlib.import_module('pages.workout_logger')

    # Reload modules to pick up code changes (fixes Streamlit Cloud caching)
    importlib.reload(dashboard)
    importlib.reload(generate_plan)
    importlib.reload(view_plans)
    importlib.reload(progress)
    importlib.reload(weekly_review)
    importlib.reload(exercise_history)
    importlib.reload(workout_logger)
except ImportError as e:
    st.error(f"Critical error loading pages: {e}")
    st.code(f"Python path: {sys.path}")
    st.code(f"Current directory: {os.getcwd()}")
    st.code(f"Directory contents: {os.listdir(os.getcwd())}")
    st.stop()

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
        except (AttributeError, KeyError):
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

# CSS - Critical Fixes + Mobile Responsiveness
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

    /* Mobile responsiveness */
    @media (max-width: 768px) {
        .main-header {
            font-size: 1.5rem !important;
        }
        .sub-header {
            font-size: 1rem !important;
        }
        /* Ensure minimum readable font sizes */
        body, p, span, div {
            font-size: max(0.9rem, 14px) !important;
        }
        /* Make day cards stack better on mobile */
        .day-card {
            min-width: 80px !important;
            padding: 0.5rem !important;
            font-size: 0.85rem !important;
        }
        /* Responsive exercise metric grids */
        div[style*="grid-template-columns: repeat(4"] {
            grid-template-columns: repeat(2, 1fr) !important;
        }
        /* Stack columns on very small screens */
        [data-testid="column"] {
            min-width: 100% !important;
        }
    }
    
    @media (max-width: 480px) {
        .main-header {
            font-size: 1.25rem !important;
        }
        /* Single column grid on very small screens */
        div[style*="grid-template-columns: repeat(4"] {
            grid-template-columns: repeat(2, 1fr) !important;
            gap: 0.25rem !important;
        }
        div[style*="grid-template-columns: repeat(4"] > div {
            padding: 0.35rem !important;
        }
    }

    /* Ensure touch targets are large enough */
    button {
        min-height: 44px !important;
        padding: 0.75rem !important;
        transition: all 0.2s ease !important;
    }
    
    /* Subtle hover effects */
    button:hover {
        transform: translateY(-1px) !important;
        box-shadow: 0 2px 4px rgba(0,0,0,0.15) !important;
    }
    
    button:active {
        transform: translateY(1px) !important;
        box-shadow: 0 1px 2px rgba(0,0,0,0.1) !important;
    }
    
    /* Exercise card consistency */
    .exercise-card {
        border: 2px solid #000;
        background: #fff;
        transition: transform 0.15s ease, box-shadow 0.15s ease;
    }
    
    .exercise-card:hover {
        transform: translateY(-2px);
        box-shadow: 0 4px 8px rgba(0,0,0,0.1);
    }
    
    /* Today's card pulse animation */
    .day-card.today {
        animation: pulse 2s infinite;
    }
    
    @keyframes pulse {
        0%, 100% { box-shadow: 0 0 0 0 rgba(0,255,0,0.4); }
        50% { box-shadow: 0 0 0 4px rgba(0,255,0,0); }
    }
    
    /* Smooth metric transitions */
    [data-testid="stMetric"] {
        transition: transform 0.2s ease;
    }
    
    [data-testid="stMetric"]:hover {
        transform: scale(1.02);
    }
    
    /* Consistent accent colors */
    .stButton>button {
        background-color: #000 !important;
        color: #fff !important;
    }
    
    .stButton>button:hover {
        background-color: #333 !important;
    }
    
    .stButton>button[kind="primary"] {
        background-color: #000 !important;
        border: 2px solid #000 !important;
    }

    input, textarea {
        min-height: 44px !important;
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
    # Deployment trigger: v1.0.1

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
    dashboard.show()
elif st.session_state.current_page == 'generate':
    generate_plan.show()
elif st.session_state.current_page == 'plans':
    view_plans.show()
elif st.session_state.current_page == 'progress':
    progress.show()
elif st.session_state.current_page == 'weekly_review':
    weekly_review.show()
elif st.session_state.current_page == 'exercise_history':
    exercise_history.show()
elif st.session_state.current_page == 'log_workout':
    workout_logger.show()
