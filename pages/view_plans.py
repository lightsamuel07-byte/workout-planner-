"""
View Plans page - Display generated workout plans
"""

import streamlit as st
import os
import glob
import re
from src.ui_utils import render_page_header, nav_button

def get_all_plans():
    """Get all workout plan files sorted by date (newest first)"""
    output_dir = "output"
    if not os.path.exists(output_dir):
        return []

    md_files = glob.glob(os.path.join(output_dir, "workout_plan_*.md"))
    md_files.sort(reverse=True)
    return md_files

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
    day_pattern = r'## ([A-Z]+DAY[^#]*)'

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

    # Get all plans
    plans = get_all_plans()

    if not plans:
        st.markdown("""
        <div style="text-align:center;padding:3rem 2rem;background:#f8f9fa;border-radius:12px;margin:2rem 0;">
            <div style="font-size:4rem;margin-bottom:1rem;">📋</div>
            <div style="font-size:1.25rem;font-weight:600;margin-bottom:0.5rem;">No Plans Yet</div>
            <div style="color:#666;margin-bottom:1.5rem;">Create your first workout plan to start tracking!</div>
        </div>
        """, unsafe_allow_html=True)
        nav_button("Generate Plan Now", "generate", "🚀", type="primary")
        return

    # Plan selector
    st.markdown("### 📁 Select a Plan")

    plan_options = []
    for plan_path in plans:
        filename = os.path.basename(plan_path)
        # Extract timestamp from filename
        timestamp_match = re.search(r'workout_plan_(\d{8})_(\d{6})', filename)
        if timestamp_match:
            date_str = timestamp_match.group(1)
            time_str = timestamp_match.group(2)
            formatted_date = f"{date_str[:4]}-{date_str[4:6]}-{date_str[6:8]} {time_str[:2]}:{time_str[2:4]}"
            plan_options.append((formatted_date, plan_path))
        else:
            plan_options.append((filename, plan_path))

    selected_plan_display = st.selectbox(
        "Choose a plan to view",
        options=range(len(plan_options)),
        format_func=lambda i: plan_options[i][0]
    )

    selected_plan_path = plan_options[selected_plan_display][1]

    st.markdown("---")

    # Parse and display the selected plan
    days = parse_plan_content(selected_plan_path)

    # Day navigation tabs
    day_names = list(days.keys())
    selected_day = st.radio(
        "Select Day",
        options=day_names,
        horizontal=True,
        key="day_selector"
    )

    st.markdown("---")

    # Display selected day
    st.markdown(f"## {selected_day}")

    day_content = days[selected_day]
    exercises = parse_exercises(day_content)

    if not exercises:
        st.markdown("""
        <div style="text-align:center;padding:2rem;background:#f0f2f6;border-radius:8px;">
            <div style="font-size:3rem;margin-bottom:1rem;">😌</div>
            <div style="font-weight:600;margin-bottom:0.5rem;">Rest Day</div>
            <div style="color:#666;">No exercises scheduled - time to recover!</div>
        </div>
        """, unsafe_allow_html=True)
        # Show raw content for rest days
        st.markdown(day_content)
    else:
        # Display exercises in clean format
        for idx, ex in enumerate(exercises):
            bg_color = '#FFF' if idx % 2 == 0 else '#f8f8f8'

            with st.container():
                st.markdown(f"""
                <div class="exercise-block" style="background-color: {bg_color};">
                    <div style="display: flex; justify-content: space-between; align-items: start; border-bottom: 3px solid #000; padding-bottom: 0.5rem; margin-bottom: 0.75rem;">
                        <div style="flex: 1;">
                            <div style="font-size: 1.5rem; color: #000; font-weight: 700; font-family: 'Space Grotesk', sans-serif;">{ex['block']}</div>
                            <div style="font-size: 1.1rem; font-weight: 700; margin: 0.25rem 0; color: #000; text-transform: uppercase;">{ex['name']}</div>
                        </div>
                    </div>
                    <div style="margin-top: 0.75rem; display: grid; grid-template-columns: repeat(4, 1fr); gap: 0.5rem;">
                        <div style="border: 2px solid #000; padding: 0.5rem; background-color: #FFF;">
                            <div style="font-size: 0.7rem; color: #000; font-weight: 700; text-transform: uppercase;">SETS</div>
                            <div style="font-weight: 700; color: #000; font-size: 1.2rem;">{ex['sets'] if ex['sets'] else '-'}</div>
                        </div>
                        <div style="border: 2px solid #000; padding: 0.5rem; background-color: #FFF;">
                            <div style="font-size: 0.7rem; color: #000; font-weight: 700; text-transform: uppercase;">REPS</div>
                            <div style="font-weight: 700; color: #000; font-size: 1.2rem;">{ex['reps'] if ex['reps'] else '-'}</div>
                        </div>
                        <div style="border: 2px solid #000; padding: 0.5rem; background-color: #FFF;">
                            <div style="font-size: 0.7rem; color: #000; font-weight: 700; text-transform: uppercase;">LOAD</div>
                            <div style="font-weight: 700; color: #000; font-size: 1.2rem;">{ex['load'] if ex['load'] else '-'}</div>
                        </div>
                        <div style="border: 2px solid #000; padding: 0.5rem; background-color: #FFF;">
                            <div style="font-size: 0.7rem; color: #000; font-weight: 700; text-transform: uppercase;">REST</div>
                            <div style="font-weight: 700; color: #000; font-size: 1.2rem;">{ex['rest'] if ex['rest'] else '-'}</div>
                        </div>
                    </div>
                    {f'<div style="margin-top: 0.75rem; padding: 0.75rem; background-color: #000; color: #0F0; border: 3px solid #0F0; font-size: 0.9rem; font-weight: 700;">📝 {ex["notes"]}</div>' if ex['notes'] else ''}
                </div>
                """, unsafe_allow_html=True)

        st.markdown(f"<br>**Total exercises:** {len(exercises)}", unsafe_allow_html=True)

    st.markdown("---")

    # Action buttons
    col1, col2, col3 = st.columns(3)

    with col1:
        if st.button("📊 Open in Google Sheets", use_container_width=True):
            sheets_url = "https://docs.google.com/spreadsheets/d/1S9Bh_f69Hgy4iqgtqT9F-t1CR6eiN9e6xJecyHyDBYU"
            st.markdown(f"[Open Google Sheets]({sheets_url})")

    with col2:
        if st.button("📄 View Markdown File", use_container_width=True):
            try:
                with open(selected_plan_path, 'r') as f:
                    markdown_content = f.read()
                with st.expander("Full Markdown Content"):
                    st.code(markdown_content, language='markdown')
            except FileNotFoundError:
                st.error("Plan file not found. It may have been deleted.")
            except Exception as e:
                st.error(f"Error reading file: {e}")

    with col3:
        if st.button("🏠 Back to Dashboard", use_container_width=True):
            st.session_state.current_page = 'dashboard'
            st.rerun()
