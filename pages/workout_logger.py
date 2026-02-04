"""
Workout Logger page - Log today's workout in real-time
"""

import streamlit as st
from datetime import datetime
import html
import re
import yaml
from src.ui_utils import (
    render_page_header, 
    get_authenticated_reader, 
    action_button, 
    empty_state,
    progress_bar
)
from src.design_system import get_colors
from src.workout_sync import sync_workout_logs_to_db


RPE_VALUE_RE = re.compile(r"\brpe\s*[:=]?\s*(\d+(?:\.\d+)?)\b", re.IGNORECASE)
RPE_OPTIONS = [""] + [f"{step / 2:.1f}".rstrip("0").rstrip(".") for step in range(2, 21)]  # 1 -> 10


def _format_rpe_value(value):
    return f"{float(value):.1f}".rstrip("0").rstrip(".")


def parse_existing_log_fields(log_text):
    """Split existing freeform log text into performance, RPE, and notes fields."""
    text = (log_text or "").strip()
    if not text:
        return "", "", ""

    parts = [p.strip() for p in text.split("|") if p.strip()]
    if not parts:
        return text, "", ""

    performance_parts = []
    notes_parts = []
    rpe_value = ""

    for part in parts:
        lower_part = part.lower()

        rpe_match = RPE_VALUE_RE.search(part)
        if rpe_match:
            numeric = float(rpe_match.group(1))
            if 1.0 <= numeric <= 10.0:
                rpe_value = _format_rpe_value(numeric)
                continue

        if lower_part.startswith("note:") or lower_part.startswith("notes:"):
            notes_parts.append(part.split(":", 1)[1].strip())
        else:
            performance_parts.append(part)

    performance = " | ".join(performance_parts).strip()
    notes = " | ".join([n for n in notes_parts if n]).strip()

    if not performance and not notes and not rpe_value:
        performance = text

    return performance, rpe_value, notes


def build_log_entry(performance, rpe, notes):
    """Compose consistent log output for Google Sheets."""
    segments = []
    performance = (performance or "").strip()
    rpe = (rpe or "").strip()
    notes = (notes or "").strip()

    if performance:
        segments.append(performance)
    if rpe:
        segments.append(f"RPE {_format_rpe_value(rpe)}")
    if notes:
        segments.append(f"Notes: {notes}")

    return " | ".join(segments)


def get_database_path():
    """Read DB path from config, with sane default."""
    try:
        with open("config.yaml", "r", encoding="utf-8") as f:
            config = yaml.safe_load(f) or {}
        return (config.get("database", {}) or {}).get("path") or "data/workout_history.db"
    except (OSError, yaml.YAMLError):
        return "data/workout_history.db"


def show():
    """Render the workout logger page"""

    # Get today's date
    today = datetime.now()
    day_name = today.strftime("%A")
    date_str = today.strftime("%B %d, %Y")

    render_page_header("Log Workout", f"{day_name}, {date_str}", "📝")

    try:
        # Get authenticated reader
        reader = get_authenticated_reader()

        # Get the most recent weekly plan sheet
        all_sheets = reader.get_all_weekly_plan_sheets()

        if not all_sheets:
            empty_state(
                "📝",
                "No Workout Plan",
                "Generate a plan first, then come back to log your workouts!"
            )
            action_button("Generate Plan Now", "generate", "🚀", accent=True, use_container_width=True)
            return

        # Use the most recent sheet
        current_sheet = all_sheets[-1]
        reader.sheet_name = current_sheet

        # Read the current week's plan
        week_data = reader.read_workout_history()

        if not week_data:
            st.markdown("""
            <div style="text-align:center;padding:2rem;background:#f0f2f6;border-radius:8px;">
                <div style="font-size:3rem;margin-bottom:1rem;">📊</div>
                <div style="font-weight:600;margin-bottom:0.5rem;">Empty Sheet</div>
                <div style="color:#666;">The sheet `{current_sheet}` exists but has no workout data.</div>
            </div>
            """, unsafe_allow_html=True)
            return

        # Find today's workout (case-insensitive)
        todays_workout = None
        for workout in week_data:
            workout_date = workout.get('date', '')
            if day_name.lower() in workout_date.lower():
                todays_workout = workout
                break

        if not todays_workout:
            empty_state(
                "😌",
                "Rest Day",
                f"No workout scheduled for {day_name}. Enjoy your recovery!"
            )
            action_button("Back to Dashboard", "dashboard", "🏠", use_container_width=True)
            return

        # Display today's workout plan
        exercises = todays_workout.get('exercises', [])

        if not exercises:
            st.markdown("""
            <div style="text-align:center;padding:2rem;background:linear-gradient(135deg, #f0f2f6 0%, #e8eaf0 100%);border-radius:12px;border:2px solid #ddd;">
                <div style="font-size:3rem;margin-bottom:1rem;">🤔</div>
                <div style="font-weight:700;margin-bottom:0.5rem;font-size:1.3rem;">No Exercises Found</div>
                <div style="color:#666;margin-bottom:1.5rem;">Today's workout appears empty.</div>
                <div style="text-align:left;display:inline-block;background:white;padding:1rem;border-radius:8px;border-left:4px solid #00D4AA;">
                    <div style="font-weight:600;margin-bottom:0.5rem;">💡 Troubleshooting:</div>
                    <div style="font-size:0.9rem;color:#666;">
                        • Check if your plan is generated in Google Sheets<br>
                        • Verify the correct week is selected<br>
                        • Make sure today's date matches the plan<br>
                        • Try refreshing the page
                    </div>
                </div>
            </div>
            """, unsafe_allow_html=True)
            st.markdown("<br>", unsafe_allow_html=True)
            col1, col2 = st.columns(2)
            with col1:
                action_button("View Plan", "plans", "📋", use_container_width=True)
            with col2:
                action_button("Back to Dashboard", "dashboard", "🏠", use_container_width=True)
            return

        # Progress display with bar
        logged_count = sum(1 for ex in exercises if ex.get('log', '').strip())
        if logged_count > 0 or 'workout_logs' in st.session_state:
            session_logged = 0
            for idx in range(len(exercises)):
                performance = st.session_state.get('workout_logs', {}).get(f"log_{idx}", "").strip()
                rpe_value = st.session_state.get('workout_rpe', {}).get(f"rpe_{idx}", "").strip()
                note_value = st.session_state.get('workout_notes', {}).get(f"note_{idx}", "").strip()
                if performance or rpe_value or note_value:
                    session_logged += 1
            total_logged = max(logged_count, session_logged)
            completion_percentage = (total_logged / len(exercises) * 100) if len(exercises) > 0 else 0
            colors = get_colors()
            completion_emoji = "🏆" if completion_percentage == 100 else "🏋️"
            
            # Show celebration for 100% completion
            if completion_percentage == 100:
                border_color = colors['accent']
                background = f"linear-gradient(135deg, rgba(0, 212, 170, 0.1) 0%, rgba(0, 230, 118, 0.1) 100%)"
                message = "🎉 Amazing work! All exercises logged!"
            else:
                border_color = colors['border_strong']
                background = f"linear-gradient(135deg, {colors['surface']} 0%, {colors['background']} 100%)"
                message = "Keep going! 💪"

            st.markdown(f"""
            <div style="background: {background}; border: 2px solid {border_color}; padding: 1.5rem; border-radius: 12px; margin: 2rem 0;">
                <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 1rem;">
                    <div>
                        <div style="font-size: 2rem; font-weight: 700; color: {colors['text_primary']};">{total_logged}/{len(exercises)} Complete</div>
                        <div style="color: {colors['text_secondary']}; margin-top: 0.5rem; font-size: 1.1rem;">{completion_percentage:.0f}% Complete</div>
                        <div style="color: {colors['accent']}; margin-top: 0.5rem; font-weight: 600;">{message}</div>
                    </div>
                    <div style="font-size: 3rem;">{completion_emoji}</div>
                </div>
                <div style="background: #e0e0e0; height: 12px; border-radius: 6px; overflow: hidden; margin-top: 1rem;">
                    <div style="
                        background: linear-gradient(90deg, {colors['accent']} 0%, #00e676 100%);
                        height: 100%;
                        width: {completion_percentage}%;
                        transition: width 0.3s ease;
                        box-shadow: 0 2px 4px rgba(0, 212, 170, 0.3);
                    "></div>
                </div>
            </div>
            """, unsafe_allow_html=True)

        st.markdown(f"### 🏋️ Today's Workout: {todays_workout.get('date', '')}")
        st.markdown("---")

        # Initialize session state for logging
        if 'workout_logs' not in st.session_state:
            st.session_state.workout_logs = {}
        if 'workout_rpe' not in st.session_state:
            st.session_state.workout_rpe = {}
        if 'workout_notes' not in st.session_state:
            st.session_state.workout_notes = {}
        if 'last_save_time' not in st.session_state:
            st.session_state.last_save_time = None

        # Group exercises by block
        blocks = {}
        for i, exercise in enumerate(exercises):
            block = exercise.get('block', 'Other')
            if block not in blocks:
                blocks[block] = []
            blocks[block].append((i, exercise))

        # Display each block with logging inputs
        for block_name, block_exercises in blocks.items():
            if block_name and block_name != 'Other':
                st.markdown("---")
                st.markdown(f"### {block_name}")

            for idx, ex in block_exercises:
                exercise_name = ex.get('exercise', 'Unknown Exercise')
                sets = ex.get('sets', '')
                reps = ex.get('reps', '')
                load = ex.get('load', '')
                rest = ex.get('rest', '')
                notes = ex.get('notes', '')
                existing_log = ex.get('log', '')

                # Create a card for each exercise
                with st.container():
                    col1, col2 = st.columns([2, 1])

                    with col1:
                        # Exercise name
                        st.markdown(f"**{exercise_name}**")

                        # 4-column grid for metrics with improved styling
                        st.markdown(f"""
                        <div style="display: grid; grid-template-columns: repeat(4, 1fr); gap: 0.5rem; margin: 0.75rem 0;">
                            <div style="border: 2px solid #1a1a1a; padding: 0.75rem 0.5rem; background: #fff; border-radius: 4px;">
                                <div style="font-size: 0.7rem; text-transform: uppercase; font-weight: 700; color: #666; letter-spacing: 0.5px; margin-bottom: 0.25rem;">SETS</div>
                                <div style="font-weight: 700; font-size: 0.95rem;">{html.escape(sets) if sets else '-'}</div>
                            </div>
                            <div style="border: 2px solid #1a1a1a; padding: 0.75rem 0.5rem; background: #fff; border-radius: 4px;">
                                <div style="font-size: 0.7rem; text-transform: uppercase; font-weight: 700; color: #666; letter-spacing: 0.5px; margin-bottom: 0.25rem;">REPS</div>
                                <div style="font-weight: 700; font-size: 0.95rem;">{html.escape(reps) if reps else '-'}</div>
                            </div>
                            <div style="border: 2px solid #1a1a1a; padding: 0.75rem 0.5rem; background: #fff; border-radius: 4px;">
                                <div style="font-size: 0.7rem; text-transform: uppercase; font-weight: 700; color: #666; letter-spacing: 0.5px; margin-bottom: 0.25rem;">LOAD</div>
                                <div style="font-weight: 700; font-size: 0.95rem;">{html.escape(load) if load else '-'}</div>
                            </div>
                            <div style="border: 2px solid #1a1a1a; padding: 0.75rem 0.5rem; background: #fff; border-radius: 4px;">
                                <div style="font-size: 0.7rem; text-transform: uppercase; font-weight: 700; color: #666; letter-spacing: 0.5px; margin-bottom: 0.25rem;">REST</div>
                                <div style="font-weight: 700; font-size: 0.95rem;">{html.escape(rest) if rest else '-'}</div>
                            </div>
                        </div>
                        """, unsafe_allow_html=True)

                        # Notes below grid
                        if notes:
                            st.markdown(f"<span style='color: #888; font-size: 0.9rem; font-style: italic;'>💡 {html.escape(notes)}</span>", unsafe_allow_html=True)

                    with col2:
                        # Logging input
                        log_key = f"log_{idx}"
                        rpe_key = f"rpe_{idx}"
                        note_key = f"note_{idx}"
                        edit_key = f"edit_mode_{idx}"

                        # Show existing log if present (unless manually editing)
                        if existing_log and not st.session_state.get(edit_key):
                            st.markdown(f"<div style='background-color: #d4edda; padding: 0.5rem; border-radius: 4px; margin-top: 0.5rem;'><span style='color: #155724; font-size: 0.9rem;'>✅ Logged: {html.escape(existing_log)}</span></div>", unsafe_allow_html=True)

                            parsed_perf, parsed_rpe, parsed_note = parse_existing_log_fields(existing_log)
                            parsed_parts = []
                            if parsed_rpe:
                                parsed_parts.append(f"RPE {parsed_rpe}")
                            if parsed_note:
                                parsed_parts.append("Has notes")
                            if parsed_parts:
                                st.caption(" • ".join(parsed_parts))

                            # Enter edit mode
                            if st.button("✏️ Edit", key=f"edit_{idx}", use_container_width=True):
                                st.session_state.workout_logs[log_key] = parsed_perf
                                if parsed_rpe:
                                    st.session_state.workout_rpe[rpe_key] = parsed_rpe
                                if parsed_note:
                                    st.session_state.workout_notes[note_key] = parsed_note
                                st.session_state[edit_key] = True
                                st.rerun()
                        else:
                            # Detect exercise type for smart placeholder
                            exercise_lower = exercise_name.lower()
                            is_cardio = any(word in exercise_lower for word in ['walk', 'run', 'bike', 'row', 'ski', 'swim'])

                            if is_cardio:
                                placeholder = "e.g., 10 min @ 3.4mph @ 6% or Done"
                                help_text = "Log duration, speed, incline OR just 'Done' if completed as prescribed"
                            else:
                                placeholder = "e.g., 12,12,11,10 @ 7kg or 12,12,11,10"
                                help_text = "Log reps per set @ weight OR just reps (e.g., 12,12,11,10)"

                            # Quick action buttons
                            qcol1, qcol2 = st.columns(2)
                            with qcol1:
                                if st.button("✓ Done", key=f"done_{idx}", use_container_width=True, help="Mark as completed as prescribed"):
                                    st.session_state.workout_logs[log_key] = "Done"
                                    st.session_state[f"input_{log_key}"] = "Done"
                                    st.rerun()
                            with qcol2:
                                if st.button("⊗ Skip", key=f"skip_{idx}", use_container_width=True, help="Mark as skipped"):
                                    st.session_state.workout_logs[log_key] = "Skipped"
                                    st.session_state[f"input_{log_key}"] = "Skipped"
                                    st.rerun()

                            # Hydrate defaults once when editing existing logs
                            if existing_log and st.session_state.get(edit_key):
                                has_local_values = (
                                    log_key in st.session_state.workout_logs
                                    or rpe_key in st.session_state.workout_rpe
                                    or note_key in st.session_state.workout_notes
                                )
                                if not has_local_values:
                                    parsed_perf, parsed_rpe, parsed_note = parse_existing_log_fields(existing_log)
                                    st.session_state.workout_logs[log_key] = parsed_perf
                                    if parsed_rpe:
                                        st.session_state.workout_rpe[rpe_key] = parsed_rpe
                                    if parsed_note:
                                        st.session_state.workout_notes[note_key] = parsed_note

                            default_value = st.session_state.workout_logs.get(log_key, "")
                            log_input = st.text_input(
                                "Performance",
                                value=default_value,
                                placeholder=placeholder,
                                key=f"input_{log_key}",
                                help=help_text,
                                label_visibility="collapsed"
                            )

                            current_rpe = st.session_state.workout_rpe.get(rpe_key, "")
                            if current_rpe not in RPE_OPTIONS:
                                current_rpe = ""
                            rpe_input = st.selectbox(
                                "RPE (Optional)",
                                options=RPE_OPTIONS,
                                index=RPE_OPTIONS.index(current_rpe),
                                key=f"input_{rpe_key}",
                                help="RPE scale 1-10 (0.5 increments)",
                                label_visibility="collapsed"
                            )

                            note_default = st.session_state.workout_notes.get(note_key, "")
                            note_input = st.text_input(
                                "Notes (Optional)",
                                value=note_default,
                                placeholder="Optional notes (pain, form, fatigue, etc.)",
                                key=f"input_{note_key}",
                                label_visibility="collapsed"
                            )

                            if log_input.strip():
                                st.session_state.workout_logs[log_key] = log_input.strip()
                            else:
                                st.session_state.workout_logs.pop(log_key, None)

                            if rpe_input:
                                st.session_state.workout_rpe[rpe_key] = rpe_input
                            else:
                                st.session_state.workout_rpe.pop(rpe_key, None)

                            if note_input.strip():
                                st.session_state.workout_notes[note_key] = note_input.strip()
                            else:
                                st.session_state.workout_notes.pop(note_key, None)

                st.markdown("<br>", unsafe_allow_html=True)

        st.markdown("---")

        # Sticky save bar for mobile - always visible at bottom
        st.markdown("""
        <style>
        .save-button-container {
            position: sticky;
            bottom: 0;
            background: white;
            padding: 1rem;
            border-top: 2px solid #000;
            z-index: 999;
            margin: 0 -1rem;
        }
        @media (max-width: 768px) {
            .save-button-container {
                position: fixed;
                bottom: 0;
                left: 0;
                right: 0;
                padding: 1rem;
                box-shadow: 0 -2px 10px rgba(0,0,0,0.1);
            }
        }
        </style>
        """, unsafe_allow_html=True)

        # Count how many exercises have logs
        logs_count = 0
        for idx in range(len(exercises)):
            performance = st.session_state.workout_logs.get(f"log_{idx}", "").strip()
            rpe_value = st.session_state.workout_rpe.get(f"rpe_{idx}", "").strip()
            note_value = st.session_state.workout_notes.get(f"note_{idx}", "").strip()
            if performance or rpe_value or note_value:
                logs_count += 1
        
        colors = get_colors()

        # Show save status with accent color
        if 'last_save_time' in st.session_state and st.session_state.last_save_time:
            save_time = st.session_state.last_save_time
            st.markdown(f"""
            <div style="background: rgba(0, 200, 83, 0.1); border-left: 4px solid #00C853; padding: 1rem; border-radius: 4px; margin: 1rem 0;">
                ✅ <strong>Last saved: {save_time}</strong> ({logs_count}/{len(exercises)} exercises logged)
            </div>
            """, unsafe_allow_html=True)
        elif logs_count > 0:
            st.markdown(f"""
            <div style="background: rgba(255, 152, 0, 0.1); border-left: 4px solid {colors['accent']}; padding: 1rem; border-radius: 4px; margin: 1rem 0;">
                📝 <strong>{logs_count}/{len(exercises)} exercises logged</strong> - Don't forget to save!
            </div>
            """, unsafe_allow_html=True)
        else:
            st.info("💡 Enter your workout data above, then click Save to store it in Google Sheets")

        st.caption("Saved in Google Sheet Log column as: `performance | RPE x | Notes: ...`")

        # Add pulsing animation CSS for save button when unsaved changes
        if logs_count > 0 and not st.session_state.get('last_save_time'):
            st.markdown("""
            <style>
            @keyframes pulse {
                0% { box-shadow: 0 0 0 0 rgba(0, 212, 170, 0.7); }
                70% { box-shadow: 0 0 0 10px rgba(0, 212, 170, 0); }
                100% { box-shadow: 0 0 0 0 rgba(0, 212, 170, 0); }
            }
            button[kind="primary"] {
                animation: pulse 2s infinite;
            }
            </style>
            """, unsafe_allow_html=True)
        
        # Save button
        col1, col2, col3 = st.columns([1, 2, 1])

        with col1:
            action_button("Back to Dashboard", "dashboard", "🏠", use_container_width=True)

        with col2:
            save_button_key = "save_workout_main"
            save_button_label = "💾 Save (Sheets + DB)" if logs_count == 0 else f"💾 Save {logs_count} Exercise{'s' if logs_count != 1 else ''} (Sheets + DB)"
            if st.button(save_button_label, type="primary", use_container_width=True, help="Saves all workout logs to your Google Sheet", key=save_button_key):
                # Prepare log data to write back to sheets
                logs_to_save = []
                db_entries = []

                for idx, ex in enumerate(exercises):
                    log_key = f"log_{idx}"
                    rpe_key = f"rpe_{idx}"
                    note_key = f"note_{idx}"
                    performance_value = st.session_state.workout_logs.get(log_key, "")
                    rpe_value = st.session_state.workout_rpe.get(rpe_key, "")
                    note_value = st.session_state.workout_notes.get(note_key, "")
                    log_value = build_log_entry(performance_value, rpe_value, note_value)

                    logs_to_save.append({
                        'exercise': ex.get('exercise', ''),
                        'log': log_value
                    })
                    if log_value.strip():
                        db_entries.append({
                            "source_row": idx + 1,
                            "exercise_name": ex.get('exercise', ''),
                            "block": ex.get('block', ''),
                            "prescribed_sets": ex.get('sets', ''),
                            "prescribed_reps": ex.get('reps', ''),
                            "prescribed_load": ex.get('load', ''),
                            "prescribed_rest": ex.get('rest', ''),
                            "prescribed_notes": ex.get('notes', ''),
                            "log_text": log_value,
                            "explicit_rpe": rpe_value,
                            "parsed_notes": note_value,
                        })

                # Write logs to Google Sheets
                try:
                    with st.spinner("Saving to Google Sheets..."):
                        success = reader.write_workout_logs(todays_workout.get('date', ''), logs_to_save)

                    if success:
                        db_error = None
                        db_path = get_database_path()
                        try:
                            sync_workout_logs_to_db(
                                db_path=db_path,
                                sheet_name=current_sheet,
                                day_label=todays_workout.get('date', ''),
                                fallback_day_name=day_name,
                                fallback_date_iso=today.date().isoformat(),
                                entries=db_entries,
                            )
                        except Exception as sync_err:
                            db_error = sync_err

                        # Store save time
                        st.session_state.last_save_time = datetime.now().strftime("%I:%M %p")

                        st.success(f"✅ Saved {logs_count} exercise log{'s' if logs_count != 1 else ''} to Google Sheets!")
                        if db_error:
                            st.warning(f"⚠️ Saved to Sheets, but DB sync failed: {db_error}")
                        else:
                            st.caption(f"🗄️ Synced to local DB: `{db_path}`")
                        st.balloons()

                        # Don't clear session state or redirect - let user stay on page
                        st.rerun()
                    else:
                        st.error("❌ Failed to save workout log")
                        st.warning("""
                        **Troubleshooting Steps:**
                        1. Check your internet connection
                        2. Verify Google Sheets is accessible
                        3. Ensure today's workout exists in the sheet
                        4. Try refreshing the page and logging in again
                        """)
                        
                        # Show what was being saved for debugging
                        with st.expander("🔍 Debug: What was being saved"):
                            st.write(f"Date: {todays_workout.get('date', 'Unknown')}")
                            st.write(f"Number of logs: {len(logs_to_save)}")
                            for i, log in enumerate(logs_to_save[:3]):
                                st.write(f"{i+1}. {log['exercise']}: '{log['log'][:50]}'")

                except Exception as e:
                    st.error(f"❌ Error saving workout: {str(e)}")
                    st.warning("""
                    **Troubleshooting Steps:**
                    1. Check your internet connection
                    2. Verify Google Sheets is accessible  
                    3. Try refreshing the page
                    4. Contact support if issue persists
                    """)
                    
                    with st.expander("🔍 Technical Details"):
                        import traceback
                        st.code(traceback.format_exc())

        with col3:
            # Initialize confirm state
            if 'confirm_clear' not in st.session_state:
                st.session_state.confirm_clear = False
            
            if st.session_state.confirm_clear:
                # Show confirmation
                st.warning("⚠️ Clear all unsaved logs?")
                ccol1, ccol2 = st.columns(2)
                with ccol1:
                    if st.button("Yes, Clear", type="primary", use_container_width=True, key="confirm_clear_yes"):
                        st.session_state.workout_logs = {}
                        st.session_state.workout_rpe = {}
                        st.session_state.workout_notes = {}
                        if 'last_save_time' in st.session_state:
                            del st.session_state.last_save_time
                        st.session_state.confirm_clear = False
                        st.rerun()
                with ccol2:
                    if st.button("Cancel", use_container_width=True, key="confirm_clear_no"):
                        st.session_state.confirm_clear = False
                        st.rerun()
            else:
                if st.button("🗑️ Clear All", use_container_width=True, help="Clear all unsaved logs"):
                    st.session_state.confirm_clear = True
                    st.rerun()

    except Exception as e:
        st.error(f"Unable to load workout plan: {e}")
        st.info("Make sure you have a workout plan generated in Google Sheets.")

        action_button("Back to Dashboard", "dashboard", "🏠", use_container_width=True)
