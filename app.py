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
    
    # Get correct password
    try:
        correct_password = st.secrets.get("APP_PASSWORD", "workout2026")
    except (AttributeError, KeyError):
        correct_password = "workout2026"

    def password_entered():
        """Checks whether a password entered by the user is correct."""
        entered_password = st.session_state.get("password", "")
        
        if entered_password == correct_password:
            st.session_state["password_correct"] = True
            st.session_state["auth_token"] = "authenticated"  # Backup flag
        else:
            st.session_state["password_correct"] = False
            st.session_state["auth_token"] = None

    # Check both flags for redundancy
    is_authenticated = (
        st.session_state.get("password_correct", False) or 
        st.session_state.get("auth_token") == "authenticated"
    )
    
    if not is_authenticated:
        # Show password input
        st.markdown("## 🔒 Authentication Required")
        st.text_input(
            "Enter password to access the app:",
            type="password",
            on_change=password_entered,
            key="password"
        )
        
        if st.session_state.get("password_correct") == False:
            st.error("😕 Password incorrect. Please try again.")
        else:
            st.markdown("*This app is password-protected for authorized users only.*")
        
        return False
    else:
        # Ensure both flags are set
        st.session_state["password_correct"] = True
        st.session_state["auth_token"] = "authenticated"
        return True

if not check_password():
    st.stop()

# Debug: Show session state status (remove after fixing)
if st.session_state.get("password_correct"):
    st.sidebar.success(f"✓ Authenticated | Page: {st.session_state.get('current_page', 'unknown')}")

# Load external CSS
try:
    with open('assets/styles.css', 'r') as f:
        css_content = f.read()
    st.markdown(f"<style>{css_content}</style>", unsafe_allow_html=True)
except FileNotFoundError:
    st.warning("Custom styles not found. Using default styling.")

# Apply dark mode theme if enabled
if st.session_state.get('dark_mode', False):
    st.markdown('<div data-theme="dark" style="display:none;"></div>', unsafe_allow_html=True)

# Additional page-specific styles
st.markdown("""
    <style>
    /* Fix text area overlapping labels */
    .stTextArea label[data-testid="stWidgetLabel"] {
        display: none;
    }
    
    /* Page header styles */
    .main-header {
        font-size: 2.5rem;
        font-weight: 700;
        margin-bottom: 0.5rem;
        font-family: 'Space Grotesk', sans-serif;
    }
    
    .sub-header {
        font-size: 1.125rem;
        color: var(--color-text-secondary);
        margin-bottom: 2rem;
    }
    </style>
""", unsafe_allow_html=True)

# Initialize session state
if 'current_page' not in st.session_state:
    st.session_state.current_page = 'dashboard'
if 'dark_mode' not in st.session_state:
    st.session_state.dark_mode = False

# Sidebar navigation
with st.sidebar:
    st.markdown("# 💪 Workout Planner")
    st.markdown("---")
    
    # THIS WEEK section
    st.markdown('<div class="nav-section-header">THIS WEEK</div>', unsafe_allow_html=True)
    
    if st.button("📊 Dashboard", use_container_width=True, key="nav_dashboard", 
                 type="primary" if st.session_state.current_page == 'dashboard' else "secondary"):
        st.session_state.current_page = 'dashboard'
        st.rerun()

    if st.button("📝 Log Workout", use_container_width=True, key="nav_log_workout",
                 type="primary" if st.session_state.current_page == 'log_workout' else "secondary"):
        st.session_state.current_page = 'log_workout'
        st.rerun()

    if st.button("📋 View Plan", use_container_width=True, key="nav_plans",
                 type="primary" if st.session_state.current_page == 'plans' else "secondary"):
        st.session_state.current_page = 'plans'
        st.rerun()
    
    # PLANNING section
    st.markdown('<div class="nav-section-header">PLANNING</div>', unsafe_allow_html=True)
    
    if st.button("🆕 Generate Plan", use_container_width=True, key="nav_generate",
                 type="primary" if st.session_state.current_page == 'generate' else "secondary"):
        st.session_state.current_page = 'generate'
        st.rerun()
    
    # ANALYTICS section
    st.markdown('<div class="nav-section-header">ANALYTICS</div>', unsafe_allow_html=True)

    if st.button("📈 Progress", use_container_width=True, key="nav_progress",
                 type="primary" if st.session_state.current_page == 'progress' else "secondary"):
        st.session_state.current_page = 'progress'
        st.rerun()

    if st.button("📅 Weekly Review", use_container_width=True, key="nav_weekly_review",
                 type="primary" if st.session_state.current_page == 'weekly_review' else "secondary"):
        st.session_state.current_page = 'weekly_review'
        st.rerun()

    if st.button("📋 Exercise History", use_container_width=True, key="nav_exercise_history",
                 type="primary" if st.session_state.current_page == 'exercise_history' else "secondary"):
        st.session_state.current_page = 'exercise_history'
        st.rerun()

    st.markdown("---")
    
    # SETTINGS section
    st.markdown('<div class="nav-section-header">SETTINGS</div>', unsafe_allow_html=True)
    
    # Dark mode toggle
    dark_mode = st.checkbox("🌙 Dark Mode", value=st.session_state.dark_mode, key="dark_mode_toggle")
    if dark_mode != st.session_state.dark_mode:
        st.session_state.dark_mode = dark_mode
        st.rerun()
    
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
