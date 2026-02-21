"""
Session History Browser page - Browse past workout sessions with full detail.
"""

import os

import streamlit as st

from src.db_queries import (
    get_connection,
    get_db_path,
    get_session_exercises,
    list_sessions,
)
from src.design_system import get_colors
from src.ui_utils import action_button, empty_state, render_page_header


def show():
    """Render the session history browser page."""
    render_page_header("Session History", "Browse past workout sessions")

    db_path = get_db_path()
    if not os.path.exists(db_path):
        empty_state("", "No Database", "Build your database from the DB Status page first.")
        action_button("DB Status", "database_status", width="stretch")
        return

    conn = get_connection(db_path)
    colors = get_colors()

    try:
        sessions = list_sessions(conn, limit=60)
        if not sessions:
            empty_state("", "No Sessions", "Sync your workout data to populate session history.")
            action_button("Back to Dashboard", "dashboard", width="stretch")
            return

        # ── Summary ─────────────────────────────────────────────────
        total_sessions = len(sessions)
        total_exercises = sum(s["exercise_count"] for s in sessions)
        total_logged = sum(s["logged_count"] for s in sessions)

        c1, c2, c3 = st.columns(3)
        c1.metric("Sessions", f"{total_sessions}")
        c2.metric("Total Exercises", f"{total_exercises:,}")
        c3.metric("With Performance Logs", f"{total_logged:,}")

        st.markdown("---")

        # ── Filter ──────────────────────────────────────────────────
        col_search, col_day = st.columns([2, 1])
        with col_search:
            search = st.text_input(
                "Search sessions",
                placeholder="e.g. Week 12, Monday, Tuesday...",
                key="sh_search",
            )
        with col_day:
            day_names = sorted(
                {s["day_name"] for s in sessions if s["day_name"]},
                key=lambda d: [
                    "Monday", "Tuesday", "Wednesday", "Thursday",
                    "Friday", "Saturday", "Sunday",
                ].index(d) if d in [
                    "Monday", "Tuesday", "Wednesday", "Thursday",
                    "Friday", "Saturday", "Sunday",
                ] else 99,
            )
            day_filter = st.selectbox(
                "Filter by day",
                ["All Days"] + day_names,
                key="sh_day_filter",
            )

        filtered = list(sessions)
        if search:
            q = search.lower()
            filtered = [
                s for s in filtered
                if q in (s["sheet_name"] or "").lower()
                or q in (s["day_label"] or "").lower()
                or q in (s["day_name"] or "").lower()
                or q in (s["session_date"] or "").lower()
            ]
        if day_filter != "All Days":
            filtered = [s for s in filtered if s["day_name"] == day_filter]

        st.caption(f"Showing {len(filtered)} session(s)")

        if not filtered:
            st.info("No sessions match your filter.")
            return

        # ── Session list ────────────────────────────────────────────
        for session in filtered:
            date_str = session["session_date"] or "No date"
            day_name = session["day_name"] or ""
            day_label = session["day_label"] or ""
            ex_count = session["exercise_count"]
            logged = session["logged_count"]
            rpe_count = session["rpe_count"]

            header = f"{date_str} — {day_name}" if day_name else f"{date_str} — {day_label}"
            badge = f"{ex_count} exercises"
            if logged:
                badge += f" | {logged} logged"
            if rpe_count:
                badge += f" | {rpe_count} RPE"

            with st.expander(f"**{header}**  ({badge})"):
                st.caption(f"Sheet: {session['sheet_name']} | {day_label}")

                exercises = get_session_exercises(conn, session["id"])
                if not exercises:
                    st.info("No exercise data in this session.")
                    continue

                for ex in exercises:
                    # Build prescription string
                    rx_parts = []
                    if ex["prescribed_sets"]:
                        rx_parts.append(str(ex["prescribed_sets"]))
                    if ex["prescribed_reps"]:
                        rx_parts.append(str(ex["prescribed_reps"]))
                    rx = " x ".join(rx_parts)
                    if ex["prescribed_load"]:
                        rx = f"{rx} @ {ex['prescribed_load']}"

                    block = f"[{ex['block']}] " if ex["block"] else ""

                    st.markdown(
                        f"<div style='padding:0.4rem 0;border-bottom:1px solid {colors['border_light']};'>"
                        f"<strong>{block}{ex['exercise_name']}</strong>"
                        f"<span style='color:{colors['text_secondary']};margin-left:0.75rem;'>{rx}</span>"
                        f"</div>",
                        unsafe_allow_html=True,
                    )

                    detail_parts = []
                    if ex["log_text"]:
                        detail_parts.append(f"Logged: {ex['log_text']}")
                    if ex["parsed_rpe"] is not None:
                        detail_parts.append(f"RPE: {ex['parsed_rpe']:.1f}")
                    if ex["prescribed_notes"]:
                        detail_parts.append(f"Notes: {ex['prescribed_notes']}")

                    if detail_parts:
                        st.markdown(
                            f"<div style='color:{colors['text_secondary']};font-size:0.85rem;"
                            f"padding:0.2rem 0 0.4rem 1rem;'>"
                            + " | ".join(detail_parts)
                            + "</div>",
                            unsafe_allow_html=True,
                        )

    finally:
        conn.close()

    st.markdown("---")
    action_button("Back to Dashboard", "dashboard", width="stretch")
