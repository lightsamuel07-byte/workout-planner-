"""
Generate Plan page - Interface for creating new workout plans
"""

import streamlit as st
from datetime import datetime, timedelta
import sys
import os
from src.ui_utils import render_page_header

# Add src to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src'))

def get_next_monday():
    """Calculate the next Monday date"""
    today = datetime.now()
    days_until_monday = (7 - today.weekday()) % 7
    if days_until_monday == 0:
        next_monday = today
    else:
        next_monday = today + timedelta(days=days_until_monday)
    return next_monday

def show():
    """Render the generate plan page"""

    render_page_header("Generate New Workout Plan", "Create your personalized weekly workout plan", "🆕")

    # Calculate next Monday
    next_monday = get_next_monday()

    st.markdown(f"### 📅 Week Starting: {next_monday.strftime('%A, %B %d, %Y')}")
    st.markdown("---")

    # Step 1: Fort Workouts Input
    st.markdown("### 📋 STEP 1: Fort Workouts (Mon/Wed/Fri)")
    st.markdown("Paste your Fort trainer workouts from Train Heroic:")

    with st.expander("📝 MONDAY WORKOUT", expanded=True):
        monday_workout = st.text_area(
            label="monday_input",
            height=200,
            placeholder="Paste Monday workout here...",
            key="monday_workout",
            label_visibility="collapsed"
        )

    with st.expander("📝 WEDNESDAY WORKOUT"):
        wednesday_workout = st.text_area(
            label="wednesday_input",
            height=200,
            placeholder="Paste Wednesday workout here...",
            key="wednesday_workout",
            label_visibility="collapsed"
        )

    with st.expander("📝 FRIDAY WORKOUT"):
        friday_workout = st.text_area(
            label="friday_input",
            height=200,
            placeholder="Paste Friday workout here...",
            key="friday_workout",
            label_visibility="collapsed"
        )

    st.markdown("---")

    # Step 2: Program Status
    st.markdown("### 🔄 STEP 2: Program Status")

    is_new_program = st.radio(
        "Is this a new Fort program?",
        options=[False, True],
        format_func=lambda x: "🆕 Yes - Design fresh supplemental workouts" if x else "📈 No - Continue with progressive overload",
        key="is_new_program"
    )

    if not is_new_program:
        st.info("✅ The AI will continue your current supplemental exercises with progressive overload based on last week's performance.")
    else:
        st.info("🆕 The AI will design brand new supplemental workouts aligned with your new Fort program.")

    st.markdown("---")

    # Step 3: Review Last Week (Optional)
    st.markdown("### 📊 STEP 3: Last Week's Performance (Optional)")

    with st.expander("View Last Week's Log"):
        st.markdown("""
        📊 **Auto-loaded from Google Sheets: (Weekly Plan) 1/18/2026**

        **Last Week's Data:**
        - 60 total supplemental exercises logged
        - Tuesday: 27 exercises
        - Thursday: 23 exercises
        - Saturday: 10 exercises

        *This data will be automatically used for progressive overload recommendations.*
        """)

    st.markdown("---")

    # Validation and Generate Button
    all_workouts_filled = monday_workout and wednesday_workout and friday_workout

    if not all_workouts_filled:
        st.warning("⚠️ Please paste all three Fort workouts (Monday, Wednesday, Friday) to continue.")

    col1, col2, col3 = st.columns([1, 2, 1])

    with col2:
        generate_button = st.button(
            "🚀 Generate Workout Plan with AI",
            type="primary",
            use_container_width=True,
            disabled=not all_workouts_filled
        )

    if generate_button:
        with st.spinner("🤖 Generating your personalized workout plan..."):
            try:
                # Import after user clicks to avoid loading on page load
                from plan_generator import PlanGenerator
                from sheets_reader import SheetsReader
                from sheets_writer import SheetsWriter
                import yaml
                from dotenv import load_dotenv

                # Load config and API key
                # Load .env from the app root directory (local only)
                env_path = os.path.join(os.path.dirname(__file__), '..', '.env')
                load_dotenv(env_path)

                config_path = os.path.join(os.path.dirname(__file__), '..', 'config.yaml')
                with open(config_path, 'r') as f:
                    config = yaml.safe_load(f)

                # Try Streamlit secrets first (deployed), then environment variable (local)
                if 'ANTHROPIC_API_KEY' in st.secrets:
                    api_key = st.secrets['ANTHROPIC_API_KEY']
                else:
                    api_key = os.getenv(config['claude']['api_key_env'])

                if not api_key:
                    st.error("❌ API key not found. Please check your .env file or Streamlit secrets.")
                    return

                # Format trainer workouts
                trainer_workouts = {
                    'monday': monday_workout,
                    'wednesday': wednesday_workout,
                    'friday': friday_workout
                }

                formatted_workouts = f"""
TRAINER WORKOUTS FROM TRAIN HEROIC:

=== Monday ===
{monday_workout}

=== Wednesday ===
{wednesday_workout}

=== Friday ===
{friday_workout}
"""

                # Fixed preferences
                preferences = """
USER PREFERENCES:
• Goal: maximize aesthetics without interfering with Mon/Wed/Fri Fort program
• Training Approach: progressive overload
• Supplemental Days: Tuesday, Thursday, Saturday
• Rest Day: Sunday
"""

                # Get workout history (optional)
                workout_history = "No prior workout history available (new program)."
                if not is_new_program:
                    try:
                        sheets_reader = SheetsReader(
                            credentials_file=config['google_sheets']['credentials_file'],
                            spreadsheet_id=config['google_sheets']['spreadsheet_id'],
                            sheet_name=config['google_sheets']['sheet_name']
                        )
                        sheets_reader.authenticate()
                        prior_supplemental = sheets_reader.read_prior_week_supplemental()
                        workout_history = sheets_reader.format_supplemental_for_ai(prior_supplemental)
                    except Exception as e:
                        st.warning(f"Could not load prior week data: {e}")

                # Generate plan
                plan_gen = PlanGenerator(api_key=api_key, config=config)
                plan = plan_gen.generate_plan(workout_history, formatted_workouts, preferences)

                if plan:
                    # Save plan to markdown
                    output_file = plan_gen.save_plan(plan)

                    # Calculate sheet name
                    sheet_name = f"Weekly Plan ({next_monday.month}/{next_monday.day}/{next_monday.year})"

                    # Write to Google Sheets
                    sheets_writer = SheetsWriter(
                        credentials_file=config['google_sheets']['credentials_file'],
                        spreadsheet_id=config['google_sheets']['spreadsheet_id'],
                        sheet_name=sheet_name
                    )
                    sheets_writer.authenticate()
                    sheets_writer.write_workout_plan(plan)

                    st.success("✅ Workout plan generated successfully!")
                    st.balloons()

                    st.markdown(f"""
                    ### 🎉 Success!

                    Your workout plan has been generated and saved to:
                    - 📄 Markdown file: `{output_file}`
                    - 📊 Google Sheets: `{sheet_name}`

                    """)

                    col1, col2 = st.columns(2)
                    with col1:
                        if st.button("📋 View Generated Plan", use_container_width=True):
                            st.session_state.current_page = 'plans'
                            st.rerun()
                    with col2:
                        if st.button("📊 Back to Dashboard", use_container_width=True):
                            st.session_state.current_page = 'dashboard'
                            st.rerun()

                else:
                    st.error("❌ Failed to generate plan. Please check your API key and try again.")

            except Exception as e:
                st.error(f"❌ Error: {str(e)}")
                import traceback
                with st.expander("View Error Details"):
                    st.code(traceback.format_exc())

    # Cost estimate
    st.markdown("---")
    col1, col2 = st.columns(2)
    with col1:
        st.markdown("⏱️ **Estimated time:** 30-45 seconds")
    with col2:
        st.markdown("💰 **API cost:** ~$0.30 (Claude Sonnet 4.5)")
