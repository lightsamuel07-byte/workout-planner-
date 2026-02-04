"""
View Plans page - Display generated workout plans
"""

import streamlit as st
import os
import glob
import re
from src.ui_utils import render_page_header, action_button, empty_state, get_authenticated_reader
from src.design_system import get_colors

def get_all_plans():
    """Get all workout plan files sorted by date (newest first)"""
    output_dir = "output"
    if not os.path.exists(output_dir):
        return []

    md_files = glob.glob(os.path.join(output_dir, "workout_plan_*.md"))
    archive_dir = os.path.join(output_dir, "archive")
    if os.path.exists(archive_dir):
        md_files.extend(glob.glob(os.path.join(archive_dir, "workout_plan_*.md")))

    # Exclude explanation files (they end with _explanation.md)
    md_files = [f for f in md_files if not f.endswith('_explanation.md')]

    md_files.sort(reverse=True)
    return md_files


@st.cache_resource
def get_sheets_reader():
    """Get cached authenticated SheetsReader for plan fallback."""
    return get_authenticated_reader()


def get_sheet_plans():
    """Return weekly plan sheet names (newest first)."""
    try:
        reader = get_sheets_reader()
        sheets = reader.get_all_weekly_plan_sheets()
        return list(reversed(sheets))
    except Exception:
        return []


def read_sheet_plan(sheet_name):
    """Read one weekly plan from Google Sheets."""
    reader = get_sheets_reader()
    reader.sheet_name = sheet_name
    return reader.read_workout_history(num_recent_workouts=20)

def parse_plan_content(plan_path):
    """Parse plan file into structured sections"""
    try:
        with open(plan_path, 'r') as f:
            content = f.read()
    except FileNotFoundError:
        st.error(f"Plan file not found: {plan_path}")
        return {}
    except Exception as e:
        st.error(f"Error reading plan file: {e}")
        return {}

    # Split by days
    days = {}
    # Capture just the day name (e.g., "MONDAY", "TUESDAY") without the extra text
    day_pattern = r'## ([A-Z]+DAY)'

    matches = list(re.finditer(day_pattern, content))
    for i, match in enumerate(matches):
        day_name = match.group(1).strip()
        start = match.end()
        end = matches[i + 1].start() if i + 1 < len(matches) else len(content)
        day_content = content[start:end].strip()
        days[day_name] = day_content

    return days

def parse_exercises(day_content):
    """Parse exercises from a day's content"""
    exercises = []
    exercise_pattern = r'### ([A-Z]\d+)\. (.+?)(?=\n###|\n##|$)'

    matches = re.finditer(exercise_pattern, day_content, re.DOTALL)
    for match in matches:
        block = match.group(1)
        rest_of_line = match.group(2)

        # Extract exercise name (first line)
        lines = rest_of_line.split('\n')
        exercise_name = lines[0].strip()

        # Extract details from bullet points
        sets = reps = load = rest = notes = ""
        for line in lines[1:]:
            line = line.strip()
            if line.startswith('- ') and ' x ' in line and not sets:
                # Parse sets x reps @ load
                parts = line[2:].strip()
                if ' x ' in parts:
                    sets_match = re.search(r'(\d+)\s*x', parts)
                    if sets_match:
                        sets = sets_match.group(1)
                    reps_match = re.search(r'x\s*([\d\-:]+)', parts)
                    if reps_match:
                        reps = reps_match.group(1)
                    load_match = re.search(r'@\s*([\d\.\-]+)', parts)
                    if load_match:
                        load = load_match.group(1)
            elif '**Rest:**' in line:
                rest = line.replace('**Rest:**', '').strip().replace('- ', '')
            elif '**Notes:**' in line:
                notes = line.replace('**Notes:**', '').strip().replace('- ', '')

        exercises.append({
            'block': block,
            'name': exercise_name,
            'sets': sets,
            'reps': reps,
            'load': load,
            'rest': rest,
            'notes': notes
        })

    return exercises

def show():
    """Render the view plans page"""

    render_page_header("Workout Plans", "View your generated workout plans", "📋")

    plans = get_all_plans()
    selected_plan_path = None
    selected_sheet_name = None
    selected_day = None
    day_content = ""
    exercises = []
    data_source = "local"

    if plans:
        # Local markdown plan selector
        st.markdown("### 📁 Select a Plan")
        plan_options = []
        for plan_path in plans:
            filename = os.path.basename(plan_path)
            archived_match = re.search(r'workout_plan_(\d{8})__archived_(\d{8})_(\d{6})', filename)
            canonical_week_match = re.search(r'workout_plan_(\d{8})\.md$', filename)
            timestamp_match = re.search(r'workout_plan_(\d{8})_(\d{6})', filename)

            if archived_match:
                week_str = archived_match.group(1)
                arch_date = archived_match.group(2)
                arch_time = archived_match.group(3)
                formatted_week = f"{week_str[:4]}-{week_str[4:6]}-{week_str[6:8]}"
                formatted_archived = f"{arch_date[:4]}-{arch_date[4:6]}-{arch_date[6:8]} {arch_time[:2]}:{arch_time[2:4]}"
                plan_options.append((f"{formatted_week} (archived {formatted_archived})", plan_path))
            elif canonical_week_match:
                week_str = canonical_week_match.group(1)
                formatted_week = f"{week_str[:4]}-{week_str[4:6]}-{week_str[6:8]}"
                plan_options.append((f"{formatted_week} (current)", plan_path))
            elif timestamp_match:
                date_str = timestamp_match.group(1)
                time_str = timestamp_match.group(2)
                formatted_date = f"{date_str[:4]}-{date_str[4:6]}-{date_str[6:8]} {time_str[:2]}:{time_str[2:4]}"
                plan_options.append((formatted_date, plan_path))
            else:
                plan_options.append((filename, plan_path))

        selected_plan_display = st.selectbox(
            "Choose a plan to view",
            options=range(len(plan_options)),
            format_func=lambda i: plan_options[i][0],
            key="local_plan_selector"
        )
        selected_plan_path = plan_options[selected_plan_display][1]

        st.markdown("---")
        days = parse_plan_content(selected_plan_path)
        if not days:
            st.error("⚠️ Unable to parse workout days from this plan file.")
            st.info("The plan file may be in an unexpected format. Try generating a new plan.")
            action_button("Back to Dashboard", "dashboard", "🏠", use_container_width=True)
            return

        day_names = list(days.keys())
        if not day_names:
            st.error("⚠️ No workout days found in this plan.")
            action_button("Back to Dashboard", "dashboard", "🏠", use_container_width=True)
            return

        selected_day = st.radio(
            "Select Day",
            options=day_names,
            horizontal=True,
            key="day_selector_local"
        )
        day_content = days.get(selected_day, '')
        if not day_content:
            st.warning(f"No content found for {selected_day}")
            return
        exercises = parse_exercises(day_content)
    else:
        # Fallback to Google Sheets when local files are absent (common on Streamlit Cloud).
        data_source = "sheets"
        sheet_plans = get_sheet_plans()
        if not sheet_plans:
            empty_state(
                "📋",
                "No Plans Yet",
                "No local plan files or weekly plan sheets were found."
            )
            action_button("Generate Plan Now", "generate", "🚀", accent=True, use_container_width=True)
            return

        st.info("Showing plans from Google Sheets (no local markdown files found).")
        selected_sheet_name = st.selectbox(
            "Choose Google Sheet to view",
            options=sheet_plans,
            key="sheet_plan_selector"
        )

        workouts = read_sheet_plan(selected_sheet_name)
        if not workouts:
            st.warning(f"No workout data found in sheet `{selected_sheet_name}`.")
            action_button("Back to Dashboard", "dashboard", "🏠", use_container_width=True)
            return

        day_labels = [w.get('date', 'Unknown Day') for w in workouts]
        selected_day = st.radio(
            "Select Day",
            options=day_labels,
            horizontal=True,
            key="day_selector_sheets"
        )

        selected_workout = next((w for w in workouts if w.get('date') == selected_day), None)
        if not selected_workout:
            st.warning(f"No content found for {selected_day}")
            return

        # Normalize sheet rows to the same keys used by the renderer below.
        exercises = []
        for ex in selected_workout.get('exercises', []):
            exercises.append({
                'block': ex.get('block', ''),
                'name': ex.get('exercise', ''),
                'sets': ex.get('sets', ''),
                'reps': ex.get('reps', ''),
                'load': ex.get('load', ''),
                'rest': ex.get('rest', ''),
                'notes': ex.get('notes', ''),
            })

    st.markdown("---")
    st.markdown(f"## {selected_day}")

    colors = get_colors()
    
    if not exercises:
        empty_state(
            "😌",
            "Rest Day",
            "No exercises scheduled - time to recover!"
        )
        if day_content:
            st.markdown(day_content)
    else:
        # Display exercises in clean format
        for idx, ex in enumerate(exercises):
            with st.container():
                st.markdown(f"""
                <div class="exercise-card" style="
                    background-color: {colors['surface']};
                    border: 2px solid {colors['border_strong']};
                    border-radius: 8px;
                    padding: 1rem;
                    margin-bottom: 1rem;
                ">
                    <div style="display: flex; justify-content: space-between; align-items: start; border-bottom: 3px solid {colors['accent']}; padding-bottom: 0.5rem; margin-bottom: 0.75rem;">
                        <div style="flex: 1;">
                            <div style="font-size: 1.5rem; color: {colors['text_primary']}; font-weight: 700; font-family: 'Space Grotesk', sans-serif;">{ex['block']}</div>
                            <div style="font-size: 1.1rem; font-weight: 700; margin: 0.25rem 0; color: {colors['text_primary']}; text-transform: uppercase;">{ex['name']}</div>
                        </div>
                    </div>
                    <div style="margin-top: 0.75rem; display: grid; grid-template-columns: repeat(4, 1fr); gap: 0.5rem;">
                        <div style="border: 2px solid {colors['border_strong']}; padding: 0.5rem; background-color: {colors['surface']};">
                            <div style="font-size: 0.7rem; color: {colors['text_secondary']}; font-weight: 700; text-transform: uppercase;">SETS</div>
                            <div style="font-weight: 700; color: {colors['text_primary']}; font-size: 1.2rem;">{ex['sets'] if ex['sets'] else '-'}</div>
                        </div>
                        <div style="border: 2px solid {colors['border_strong']}; padding: 0.5rem; background-color: {colors['surface']};">
                            <div style="font-size: 0.7rem; color: {colors['text_secondary']}; font-weight: 700; text-transform: uppercase;">REPS</div>
                            <div style="font-weight: 700; color: {colors['text_primary']}; font-size: 1.2rem;">{ex['reps'] if ex['reps'] else '-'}</div>
                        </div>
                        <div style="border: 2px solid {colors['border_strong']}; padding: 0.5rem; background-color: {colors['surface']};">
                            <div style="font-size: 0.7rem; color: {colors['text_secondary']}; font-weight: 700; text-transform: uppercase;">LOAD</div>
                            <div style="font-weight: 700; color: {colors['text_primary']}; font-size: 1.2rem;">{ex['load'] if ex['load'] else '-'}</div>
                        </div>
                        <div style="border: 2px solid {colors['border_strong']}; padding: 0.5rem; background-color: {colors['surface']};">
                            <div style="font-size: 0.7rem; color: {colors['text_secondary']}; font-weight: 700; text-transform: uppercase;">REST</div>
                            <div style="font-weight: 700; color: {colors['text_primary']}; font-size: 1.2rem;">{ex['rest'] if ex['rest'] else '-'}</div>
                        </div>
                    </div>
                    {f'<div style="margin-top: 0.75rem; padding: 0.75rem; background-color: ' + colors['accent'] + '; color: ' + colors['primary'] + '; border: 2px solid ' + colors['accent'] + '; border-radius: 4px; font-size: 0.9rem; font-weight: 700;">📝 ' + ex['notes'] + '</div>' if ex['notes'] else ''}
                </div>
                """, unsafe_allow_html=True)

        st.markdown(f"<br>**Total exercises:** {len(exercises)}", unsafe_allow_html=True)

    st.markdown("---")

    # Check if explanation file exists for local markdown plans
    if data_source == "local" and selected_plan_path:
        explanation_path = selected_plan_path.replace('.md', '_explanation.md')
        if os.path.exists(explanation_path):
            with st.expander("📖 View AI Explanation (Why this plan was designed this way)", expanded=False):
                try:
                    with open(explanation_path, 'r') as f:
                        explanation_content = f.read()
                    st.markdown(explanation_content)
                except Exception as e:
                    st.error(f"Error reading explanation file: {e}")

    st.markdown("---")

    # Action buttons
    col1, col2, col3 = st.columns(3)

    try:
        spreadsheet_id = get_sheets_reader().spreadsheet_id
    except Exception:
        spreadsheet_id = "1S9Bh_f69Hgy4iqgtqT9F-t1CR6eiN9e6xJecyHyDBYU"

    with col1:
        if st.button("📊 Open in Google Sheets", use_container_width=True):
            sheets_url = f"https://docs.google.com/spreadsheets/d/{spreadsheet_id}"
            st.markdown(f"[Open Google Sheets]({sheets_url})")

    with col2:
        if data_source == "local" and st.button("📄 View Markdown File", use_container_width=True):
            try:
                with open(selected_plan_path, 'r') as f:
                    markdown_content = f.read()
                with st.expander("Full Markdown Content"):
                    st.code(markdown_content, language='markdown')
            except FileNotFoundError:
                st.error("Plan file not found. It may have been deleted.")
            except Exception as e:
                st.error(f"Error reading file: {e}")
        elif data_source == "sheets":
            st.button("📄 View Markdown File", use_container_width=True, disabled=True, help="Markdown view is only available for local file plans.")

    with col3:
        action_button("🏠 Back to Dashboard", "dashboard", use_container_width=True)
