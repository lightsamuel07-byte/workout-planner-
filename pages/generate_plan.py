"""
Generate Plan page - Interface for creating new workout plans
"""

import streamlit as st
from datetime import datetime, timedelta
import sys
import os
import shutil
from src.ui_utils import render_page_header, action_button
from src.design_system import get_colors

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

def extract_fort_workout_title(workout_text):
    if not workout_text:
        return None

    lines = [line.strip() for line in workout_text.splitlines() if line.strip()]
    head = "\n".join(lines[:12])
    import re
    match = re.search(r'(Gameday\s*#\s*\d+)', head, flags=re.IGNORECASE)
    if match:
        return match.group(1).strip()
    return None

def show():
    """Render the generate plan page"""

    render_page_header("Generate New Workout Plan", "Create your personalized weekly workout plan", "🆕")

    if 'plan_generation_in_progress' not in st.session_state:
        st.session_state.plan_generation_in_progress = False
    if 'plan_existence_checks' not in st.session_state:
        st.session_state.plan_existence_checks = {}
    if 'last_week_log_text' not in st.session_state:
        st.session_state.last_week_log_text = None
    if 'last_week_log_error' not in st.session_state:
        st.session_state.last_week_log_error = None

    # Calculate next Monday
    next_monday = get_next_monday()
    colors = get_colors()

    week_stamp = next_monday.strftime("%Y%m%d")
    output_folder = "output"
    output_file = os.path.join(output_folder, f"workout_plan_{week_stamp}.md")
    sheet_name = f"Weekly Plan ({next_monday.month}/{next_monday.day}/{next_monday.year})"

    def _run_plan_existence_checks():
        local_exists = os.path.exists(output_file)

        sheets_exists = False
        sheets_error = None
        try:
            import yaml
            from src.sheets_reader import SheetsReader

            config_path = os.path.join(os.path.dirname(__file__), '..', 'config.yaml')
            with open(config_path, 'r') as f:
                config = yaml.safe_load(f)

            sheets_reader = SheetsReader(
                credentials_file=config['google_sheets']['credentials_file'],
                spreadsheet_id=config['google_sheets']['spreadsheet_id'],
                sheet_name=config['google_sheets']['sheet_name']
            )
            sheets_reader.authenticate()
            all_weekly_sheets = sheets_reader.get_all_weekly_plan_sheets()
            sheets_exists = sheet_name in all_weekly_sheets
        except Exception as e:
            sheets_error = str(e)

        st.session_state.plan_existence_checks[week_stamp] = {
            'local_exists': local_exists,
            'sheets_exists': sheets_exists,
            'sheets_error': sheets_error
        }

    if week_stamp not in st.session_state.plan_existence_checks:
        _run_plan_existence_checks()

    # Week info card
    st.markdown(f"""
    <div style="
        background: linear-gradient(135deg, {colors['accent']}15 0%, {colors['surface']} 100%);
        border: 2px solid {colors['accent']};
        border-radius: 12px;
        padding: 1.5rem;
        margin-bottom: 2rem;
        text-align: center;
    ">
        <div style="font-size: 0.85rem; text-transform: uppercase; font-weight: 700; color: {colors['text_secondary']}; letter-spacing: 0.5px; margin-bottom: 0.5rem;">
            WEEK STARTING
        </div>
        <div style="font-size: 1.75rem; font-weight: 700; color: {colors['text_primary']};">
            📅 {next_monday.strftime('%A, %B %d, %Y')}
        </div>
    </div>
    """, unsafe_allow_html=True)

    # Step 1: Fort Workouts Input
    st.markdown("### 📋 STEP 1: Fort Workouts (Mon/Wed/Fri)")
    
    st.markdown(f"""
    <div style="
        background: {colors['surface']};
        border: 2px solid {colors['border_light']};
        border-left: 4px solid {colors['accent']};
        border-radius: 8px;
        padding: 1rem;
        margin-bottom: 1.5rem;
    ">
        <div style="font-weight: 600; margin-bottom: 0.5rem;">💡 How to use:</div>
        <div style="color: {colors['text_secondary']}; font-size: 0.9rem;">
            Copy your Fort workouts from Train Heroic and paste them into the boxes below. The AI will analyze them and create complementary supplemental exercises.
        </div>
    </div>
    """, unsafe_allow_html=True)

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
        if is_new_program:
            st.markdown("""
            🆕 **New program selected**

            Prior week data won't be used when designing a fresh supplemental program.
            """)
        else:
            if st.button("📊 Load Last Week's Log", use_container_width=True, key="load_last_week_log"):
                try:
                    import yaml
                    from src.sheets_reader import SheetsReader

                    config_path = os.path.join(os.path.dirname(__file__), '..', 'config.yaml')
                    with open(config_path, 'r') as f:
                        config = yaml.safe_load(f)

                    sheets_reader = SheetsReader(
                        credentials_file=config['google_sheets']['credentials_file'],
                        spreadsheet_id=config['google_sheets']['spreadsheet_id'],
                        sheet_name=config['google_sheets']['sheet_name']
                    )
                    sheets_reader.authenticate()
                    prior_supplemental = sheets_reader.read_prior_week_supplemental()
                    st.session_state.last_week_log_text = sheets_reader.format_supplemental_for_ai(prior_supplemental)
                    st.session_state.last_week_log_error = None
                except Exception as e:
                    st.session_state.last_week_log_error = str(e)
                    st.session_state.last_week_log_text = None

            if st.session_state.last_week_log_error:
                st.warning(f"Could not load prior week data: {st.session_state.last_week_log_error}")
            elif st.session_state.last_week_log_text:
                st.code(st.session_state.last_week_log_text)

    st.markdown("---")

    # Validation and Generate Button
    all_workouts_filled = monday_workout and wednesday_workout and friday_workout

    colors = get_colors()

    checks = st.session_state.plan_existence_checks.get(week_stamp, {})
    local_exists = checks.get('local_exists', False)
    sheets_exists = checks.get('sheets_exists', False)
    sheets_error = checks.get('sheets_error')

    if local_exists or sheets_exists:
        st.warning(
            f"A plan already exists for the week starting {next_monday.strftime('%B %d, %Y')}. "
            "Generating will archive the existing plan (local file + Google Sheets tab) and create a new current-week plan."
        )
        if local_exists:
            st.markdown(f"**Local:** `{output_file}`")
        if sheets_exists:
            st.markdown(f"**Google Sheets tab:** `{sheet_name}`")
        if sheets_error:
            st.info(f"Google Sheets check error: {sheets_error}")

        if st.button("🔄 Refresh plan checks", use_container_width=True, key="refresh_plan_checks"):
            _run_plan_existence_checks()

    if not all_workouts_filled:
        st.markdown(f"""
        <div style="background: rgba(255, 107, 53, 0.1); border-left: 4px solid {colors['warning']}; padding: 1rem; border-radius: 4px; margin: 1rem 0;">
            ⚠️ <strong>Please paste all three Fort workouts</strong> (Monday, Wednesday, Friday) to continue.
        </div>
        """, unsafe_allow_html=True)

    col1, col2, col3 = st.columns([1, 2, 1])

    with col2:
        def _start_plan_generation():
            st.session_state.plan_generation_in_progress = True

        generate_button = st.button(
            "🚀 Generate Workout Plan with AI",
            type="primary",
            use_container_width=True,
            disabled=(not all_workouts_filled) or st.session_state.plan_generation_in_progress,
            on_click=_start_plan_generation
        )

    if generate_button:
        with st.spinner("🤖 Generating your personalized workout plan..."):
            try:
                # Import after user clicks to avoid loading on page load
                from src.plan_generator import PlanGenerator
                from src.sheets_reader import SheetsReader
                from src.sheets_writer import SheetsWriter
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
                monday_title = extract_fort_workout_title(monday_workout)
                wednesday_title = extract_fort_workout_title(wednesday_workout)
                friday_title = extract_fort_workout_title(friday_workout)

                monday_header = f"Monday ({monday_title})" if monday_title else "Monday"
                wednesday_header = f"Wednesday ({wednesday_title})" if wednesday_title else "Wednesday"
                friday_header = f"Friday ({friday_title})" if friday_title else "Friday"

                trainer_workouts = {
                    'monday': monday_workout,
                    'wednesday': wednesday_workout,
                    'friday': friday_workout
                }

                formatted_workouts = f"""
TRAINER WORKOUTS FROM TRAIN HEROIC:

=== {monday_header} ===
{monday_workout}

=== {wednesday_header} ===
{wednesday_workout}

=== {friday_header} ===
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
                    os.makedirs(output_folder, exist_ok=True)
                    if os.path.exists(output_file):
                        archive_folder = os.path.join(output_folder, "archive")
                        os.makedirs(archive_folder, exist_ok=True)
                        archive_stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
                        archived_file = os.path.join(
                            archive_folder,
                            f"workout_plan_{week_stamp}__archived_{archive_stamp}.md"
                        )
                        shutil.move(output_file, archived_file)

                    with open(output_file, 'w') as f:
                        f.write(plan)

                    # Calculate sheet name
                    # Write to Google Sheets
                    sheets_writer = SheetsWriter(
                        credentials_file=config['google_sheets']['credentials_file'],
                        spreadsheet_id=config['google_sheets']['spreadsheet_id'],
                        sheet_name=sheet_name
                    )
                    sheets_writer.authenticate()

                    archived_sheet_name = f"{sheet_name} [archived {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}]"
                    sheets_writer.archive_sheet_if_exists(archived_sheet_name)
                    sheets_writer.write_workout_plan(plan)

                    st.success("✅ Workout plan generated successfully!")
                    st.balloons()

                    st.markdown(f"""
                    <div style="
                        background: rgba(0, 212, 170, 0.1);
                        border: 2px solid {colors['accent']};
                        border-radius: 8px;
                        padding: 2rem;
                        text-align: center;
                        margin: 2rem 0;
                    ">
                        <div style="font-size: 3rem; margin-bottom: 1rem;">🎉</div>
                        <div style="font-size: 1.5rem; font-weight: 700; color: {colors['text_primary']}; margin-bottom: 1rem;">Success!</div>
                        <div style="color: {colors['text_secondary']}; margin-bottom: 1rem;">
                            Your workout plan has been generated and saved to:<br>
                            📄 Markdown file: <code>{output_file}</code><br>
                            📊 Google Sheets: <code>{sheet_name}</code>
                        </div>
                    </div>
                    """, unsafe_allow_html=True)

                    col1, col2 = st.columns(2)
                    with col1:
                        action_button("📋 View Generated Plan", "plans", accent=True, use_container_width=True)
                    with col2:
                        action_button("📊 Back to Dashboard", "dashboard", use_container_width=True)

                else:
                    st.error("❌ Failed to generate plan. Please check your API key and try again.")

            except Exception as e:
                st.error(f"❌ Error: {str(e)}")
                import traceback
                with st.expander("View Error Details"):
                    st.code(traceback.format_exc())
            finally:
                st.session_state.plan_generation_in_progress = False

    # Cost estimate
    st.markdown("---")
    
    colors = get_colors()
    st.markdown(f"""
    <div style="display: flex; justify-content: space-around; padding: 1rem; background: {colors['surface']}; border: 1px solid {colors['border_light']}; border-radius: 8px;">
        <div style="text-align: center;">
            <div style="font-size: 1.5rem; margin-bottom: 0.25rem;">⏱️</div>
            <div style="font-size: 0.875rem; color: {colors['text_secondary']};">Estimated time</div>
            <div style="font-weight: 600; color: {colors['text_primary']};">30-45 seconds</div>
        </div>
        <div style="text-align: center;">
            <div style="font-size: 1.5rem; margin-bottom: 0.25rem;">💰</div>
            <div style="font-size: 0.875rem; color: {colors['text_secondary']};">API cost</div>
            <div style="font-weight: 600; color: {colors['text_primary']};">~$0.30</div>
        </div>
    </div>
    """, unsafe_allow_html=True)
