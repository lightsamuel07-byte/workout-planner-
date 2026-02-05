"""
Generate Plan page - Interface for creating new workout plans
"""

import streamlit as st
from datetime import datetime, timedelta
import sys
import os
import shutil
import re
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
    match = re.search(r'(Gameday\s*#\s*\d+)', head, flags=re.IGNORECASE)
    if match:
        return match.group(1).strip()
    return None

def strip_fort_preamble(workout_text):
    if not workout_text:
        return workout_text

    lines = workout_text.splitlines()
    nonempty = [i for i, line in enumerate(lines) if line.strip()]
    if not nonempty:
        return workout_text

    # Keep the header (date + gameday) but drop long narrative blocks.
    # Start from the first actual training section if we can find one.
    section_re = re.compile(
        r'^\s*(PREP|PRIMARY|SECONDARY|AUXILIARY|CLUSTER|MYO|T\.H\.A\.W\.|THAW)\b',
        flags=re.IGNORECASE,
    )

    section_start = None
    for i, line in enumerate(lines[:250]):
        if section_re.search(line):
            section_start = i
            break

    if section_start is None:
        return workout_text

    # Preserve up to ~12 lines of header before the first section
    header_start = nonempty[0]
    header_slice_start = max(header_start, section_start - 12)
    kept = lines[header_slice_start:]

    # Trim excessive leading blank lines
    while kept and not kept[0].strip():
        kept = kept[1:]

    return "\n".join(kept).strip() + "\n"

def extract_fort_preamble(workout_text):
    if not workout_text:
        return None

    lines = workout_text.splitlines()
    nonempty = [i for i, line in enumerate(lines) if line.strip()]
    if not nonempty:
        return None

    section_re = re.compile(
        r'^\s*(PREP|PRIMARY|SECONDARY|AUXILIARY|CLUSTER|MYO|T\.H\.A\.W\.|THAW)\b',
        flags=re.IGNORECASE,
    )

    section_start = None
    for i, line in enumerate(lines[:250]):
        if section_re.search(line):
            section_start = i
            break

    if section_start is None:
        return None

    header_start = nonempty[0]
    preamble_lines = lines[header_start:section_start]
    preamble = "\n".join(preamble_lines).strip()
    return preamble or None


def show():
    """Render the generate plan page"""

    render_page_header("Generate New Workout Plan", "Create your personalized weekly workout plan", "🆕")

    if 'plan_generation_in_progress' not in st.session_state:
        st.session_state.plan_generation_in_progress = False

    # Calculate next Monday
    next_monday = get_next_monday()
    colors = get_colors()

    # Week info card
    st.markdown(f"""
    <div style="
        background: linear-gradient(135deg, {colors['accent']}15 0%, {colors['surface']} 100%);
        border: 1px solid {colors['accent']};
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
        border: 1px solid {colors['border_light']};
        border-left: 3px solid {colors['accent']};
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

    # Step 2.5: Select Prior Week Sheet
    prior_week_sheet = None
    if not is_new_program:
        st.markdown("### 📋 STEP 2.5: Select Prior Week's Sheet")

        try:
            from src.sheets_reader import SheetsReader
            import yaml

            # Load config to get spreadsheet ID
            config_path = os.path.join(os.path.dirname(__file__), '..', 'config.yaml')
            with open(config_path, 'r') as f:
                config = yaml.safe_load(f)

            # Initialize reader to get list of sheets
            reader = SheetsReader(
                spreadsheet_id=config['google_sheets']['spreadsheet_id'],
                sheet_name=config['google_sheets']['sheet_name'],  # temp, will change
                credentials_file=config['google_sheets']['credentials_file'],
                service_account_file=config.get('google_sheets', {}).get('service_account_file')
            )
            reader.authenticate()

            # Use normalized reader logic so both naming formats are supported:
            # - "(Weekly Plan) M/D/YYYY"
            # - "Weekly Plan (M/D/YYYY)"
            weekly_sheets = list(reversed(reader.get_all_weekly_plan_sheets()))

            if weekly_sheets:
                prior_week_sheet = st.selectbox(
                    "Select which week's data to use for progressive overload:",
                    options=weekly_sheets,
                    index=0,  # Default to most recent
                    help="Choose the sheet containing last week's logged performance. The AI will use Column H (Log) data for progressive overload."
                )

                st.success(f"✅ Will read workout history from: **{prior_week_sheet}**")
            else:
                st.warning("⚠️ No weekly plan sheets found. The AI will generate workouts without prior history.")

        except Exception as e:
            st.warning(f"⚠️ Could not load sheet list: {str(e)}")
            st.info("💡 The AI will use the default sheet from config.yaml")

    st.markdown("---")

    # Step 3: Review Last Week (Optional)
    st.markdown("### 📊 STEP 3: Last Week's Performance (Optional)")

    with st.expander("View Last Week's Log"):
        if prior_week_sheet:
            st.markdown(f"""
            📊 **Auto-loaded from Google Sheets**

            *Reading workout history from: **{prior_week_sheet}***

            The AI will analyze Column H (Log) data for progressive overload recommendations.
            """)
        else:
            st.markdown("""
            📊 **Auto-loaded from Google Sheets**

            *Last week's data will be automatically loaded and used for progressive overload recommendations.*
            """)

    st.markdown("---")

    # Validation and Generate Button
    all_workouts_filled = monday_workout and wednesday_workout and friday_workout

    colors = get_colors()
    
    if not all_workouts_filled:
        st.markdown(f"""
        <div style="background: rgba(255, 107, 53, 0.1); border-left: 3px solid {colors['warning']}; padding: 1rem; border-radius: 4px; margin: 1rem 0;">
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
            width="stretch",
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
                from src.generation_context import build_db_generation_context
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
                monday_workout_clean = strip_fort_preamble(monday_workout)
                wednesday_workout_clean = strip_fort_preamble(wednesday_workout)
                friday_workout_clean = strip_fort_preamble(friday_workout)

                monday_preamble = extract_fort_preamble(monday_workout)
                wednesday_preamble = extract_fort_preamble(wednesday_workout)
                friday_preamble = extract_fort_preamble(friday_workout)

                monday_title = extract_fort_workout_title(monday_workout_clean)
                wednesday_title = extract_fort_workout_title(wednesday_workout_clean)
                friday_title = extract_fort_workout_title(friday_workout_clean)

                monday_header = f"Monday ({monday_title})" if monday_title else "Monday"
                wednesday_header = f"Wednesday ({wednesday_title})" if wednesday_title else "Wednesday"
                friday_header = f"Friday ({friday_title})" if friday_title else "Friday"


                # Use cleaned Fort text for prompt efficiency while preserving key training sections.
                monday_for_prompt = monday_workout_clean or monday_workout
                wednesday_for_prompt = wednesday_workout_clean or wednesday_workout
                friday_for_prompt = friday_workout_clean or friday_workout

                formatted_workouts = f"""
TRAINER WORKOUTS FROM TRAIN HEROIC:

=== {monday_header} ===
{monday_for_prompt}

=== {wednesday_header} ===
{wednesday_for_prompt}

=== {friday_header} ===
{friday_for_prompt}
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
                prior_supplemental = None
                db_context = None
                if not is_new_program:
                    try:
                        # Use user-selected sheet if available, otherwise fall back to config
                        sheet_to_read = prior_week_sheet if prior_week_sheet else config['google_sheets']['sheet_name']

                        sheets_reader = SheetsReader(
                            credentials_file=config['google_sheets']['credentials_file'],
                            spreadsheet_id=config['google_sheets']['spreadsheet_id'],
                            sheet_name=sheet_to_read,
                            service_account_file=config.get('google_sheets', {}).get('service_account_file')
                        )
                        sheets_reader.authenticate()
                        prior_supplemental = sheets_reader.read_supplemental_from_sheet(sheet_to_read)
                        workout_history = sheets_reader.format_supplemental_for_ai(prior_supplemental)

                        db_path = (config.get('database', {}) or {}).get('path', 'data/workout_history.db')
                        db_context = build_db_generation_context(
                            db_path=db_path,
                            prior_supplemental=prior_supplemental,
                            max_exercises=10,
                            logs_per_exercise=2,
                        )

                        st.info(f"✅ Loaded workout history from: **{sheet_to_read}**")
                        if db_context:
                            st.caption("🗄️ Added compact long-term context from local DB.")
                    except Exception as e:
                        st.warning(f"Could not load prior week data: {e}")

                # Generate plan
                plan_gen = PlanGenerator(api_key=api_key, config=config)
                fort_preamble_blocks = [p for p in [monday_preamble, wednesday_preamble, friday_preamble] if p]
                fort_preamble_text = "\n\n---\n\n".join(fort_preamble_blocks) if fort_preamble_blocks else None
                fort_week_constraints = None
                if fort_preamble_text:
                    summarize_fn = getattr(plan_gen, "summarize_fort_preamble", None)
                    if callable(summarize_fn):
                        fort_week_constraints = summarize_fn(fort_preamble_text)
                    else:
                        st.warning(
                            "Fort preamble summarization is unavailable in the currently running PlanGenerator. "
                            "Continuing without summarized Fort constraints."
                        )

                plan, explanation = plan_gen.generate_plan(
                    workout_history,
                    formatted_workouts,
                    preferences,
                    fort_week_constraints=fort_week_constraints,
                    db_context=db_context,
                )

                if plan:
                    # Save plan to markdown
                    output_folder = "output"
                    os.makedirs(output_folder, exist_ok=True)
                    week_stamp = next_monday.strftime("%Y%m%d")
                    output_file = os.path.join(output_folder, f"workout_plan_{week_stamp}.md")

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

                    if explanation:
                        explanation_file = os.path.join(output_folder, f"workout_plan_{week_stamp}_explanation.md")
                        with open(explanation_file, 'w') as f:
                            f.write(explanation)

                    # Calculate sheet name
                    sheet_name = f"Weekly Plan ({next_monday.month}/{next_monday.day}/{next_monday.year})"

                    # Write to Google Sheets
                    sheets_writer = SheetsWriter(
                        credentials_file=config['google_sheets']['credentials_file'],
                        spreadsheet_id=config['google_sheets']['spreadsheet_id'],
                        sheet_name=sheet_name,
                        service_account_file=config.get('google_sheets', {}).get('service_account_file')
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
                        border: 1px solid {colors['accent']};
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
                            📝 Explanation file: <code>{os.path.join(output_folder, f'workout_plan_{week_stamp}_explanation.md')}</code><br>
                            📊 Google Sheets: <code>{sheet_name}</code>
                        </div>
                    </div>
                    """, unsafe_allow_html=True)

                    col1, col2 = st.columns(2)
                    with col1:
                        action_button("📋 View Generated Plan", "plans", accent=True, width="stretch")
                    with col2:
                        action_button("📊 Back to Dashboard", "dashboard", width="stretch")

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
