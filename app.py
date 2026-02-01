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
# Only reload modules in development mode (set DEV_MODE=1 in environment)
DEV_MODE = os.environ.get('DEV_MODE', '0') == '1'

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

    # Reload modules only in dev mode to pick up code changes
    if DEV_MODE:
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
        # Get password from secrets, with fallback for local dev
        correct_password = None
        try:
            correct_password = st.secrets.get("APP_PASSWORD")
        except (AttributeError, KeyError):
            pass
        
        if not correct_password:
            correct_password = "workout2026"
            if not DEV_MODE:
                st.warning("⚠️ APP_PASSWORD not configured. Set it in Streamlit secrets for production.")

        entered_password = st.session_state.get("password", "")
        
        if entered_password == correct_password:
            st.session_state["password_correct"] = True
            # Clear password from session state for security
            if "password" in st.session_state:
                del st.session_state["password"]
        else:
            st.session_state["password_correct"] = False

    if "password_correct" not in st.session_state:
        # First run, show enhanced password input
        st.markdown("""
        <div style="
            max-width: 400px;
            margin: 4rem auto;
            text-align: center;
        ">
            <div style="font-size: 4rem; margin-bottom: 1rem;">💪</div>
            <h1 style="
                font-family: 'Space Grotesk', sans-serif;
                font-size: 2rem;
                font-weight: 700;
                margin-bottom: 0.5rem;
            ">Samuel's Workout Planner</h1>
            <p style="
                color: #6B7280;
                margin-bottom: 2rem;
            ">Track your strength journey</p>
        </div>
        """, unsafe_allow_html=True)
        
        col1, col2, col3 = st.columns([1, 2, 1])
        with col2:
            st.text_input(
                "Password", 
                type="password", 
                on_change=password_entered, 
                key="password",
                placeholder="Enter password to continue"
            )
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

# Additional page-specific styles with mobile responsiveness
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
    
    /* Mobile responsive styles */
    @media (max-width: 768px) {
        .main-header {
            font-size: 1.75rem;
        }
        
        .sub-header {
            font-size: 1rem;
        }
        
        /* Stack columns on mobile */
        .row-widget.stHorizontalBlock {
            flex-direction: column;
        }
        
        /* Full width buttons on mobile */
        .stButton button {
            width: 100% !important;
        }
        
        /* Better metric card spacing on mobile */
        [data-testid="metric-container"] {
            margin-bottom: 1rem;
        }
    }
    
    /* Improve scrolling on mobile */
    @media (max-width: 768px) {
        .main .block-container {
            padding-left: 1rem;
            padding-right: 1rem;
        }
    }
    
    /* Better input fields on mobile */
    @media (max-width: 768px) {
        .stTextInput input,
        .stTextArea textarea,
        .stNumberInput input {
            font-size: 16px !important; /* Prevents zoom on iOS */
        }
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
    
    # Add custom CSS for active nav buttons
    st.markdown("""
    <style>
    div[data-testid="stSidebar"] button[kind="primary"] {
        background: linear-gradient(135deg, #00D4AA 0%, #00B894 100%) !important;
        font-weight: 700 !important;
        box-shadow: 0 2px 8px rgba(0, 212, 170, 0.3) !important;
    }
    </style>
    """, unsafe_allow_html=True)
    
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
    
    # Connection status indicator
    try:
        import yaml
        from src.sheets_reader import SheetsReader
        with open('config.yaml', 'r') as f:
            config = yaml.safe_load(f)
        
        st.markdown("""
        <div style="
            padding: 0.75rem;
            background: rgba(0, 200, 83, 0.1);
            border-left: 3px solid #00C853;
            border-radius: 4px;
            font-size: 0.85rem;
        ">
            <div style="font-weight: 600; margin-bottom: 0.25rem;">🟢 Connected</div>
            <div style="color: #666; font-size: 0.8rem;">Google Sheets synced</div>
        </div>
        """, unsafe_allow_html=True)
    except Exception as e:
        st.markdown("""
        <div style="
            padding: 0.75rem;
            background: rgba(244, 67, 54, 0.1);
            border-left: 3px solid #F44336;
            border-radius: 4px;
            font-size: 0.85rem;
        ">
            <div style="font-weight: 600; margin-bottom: 0.25rem;">🔴 Disconnected</div>
            <div style="color: #666; font-size: 0.8rem;">Check your connection</div>
        </div>
        """, unsafe_allow_html=True)
    
    st.markdown("---")
    st.markdown(f"**User:** Samuel")
    st.markdown(f"**Goal:** Strength + Aesthetics")

    # Quick Tips
    st.markdown("---")
    with st.expander("💡 Quick Tips"):
        st.markdown("""
        **Logging Workouts:**
        - Use "Done" button for quick logging
        - Save regularly to avoid data loss
        - Edit button lets you fix mistakes
        
        **Navigation:**
        - Dashboard = Weekly overview
        - Log Workout = Record today's session
        - Weekly Review = See past performance
        
        **Features:**
        - 🟢 = Connected to Google Sheets
        - Progress bar shows completion %
        - All data syncs automatically
        """)
    
    # 1RM Settings
    st.markdown("---")
    st.markdown("### 🏋️ Current 1RMs")

    # Initialize session state for 1RMs from config (only on first load)
    if 'back_squat_1rm' not in st.session_state:
        # Load config once when initializing 1RMs
        try:
            with open('config.yaml', 'r') as f:
                app_config = yaml.safe_load(f)
            default_1rms = app_config.get('reference_1rms', {})
        except Exception:
            default_1rms = {'back_squat': 129, 'bench_press': 94, 'deadlift': 168}
        st.session_state.back_squat_1rm = float(default_1rms.get('back_squat', 129))
        st.session_state.bench_press_1rm = float(default_1rms.get('bench_press', 94))
        st.session_state.deadlift_1rm = float(default_1rms.get('deadlift', 168))

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
