"""
Exercise Encyclopedia page - Full searchable exercise database with history,
personal records, aliases, and progression data from SQLite.
"""

import os
import re

import streamlit as st

from src.db_queries import (
    get_connection,
    get_db_path,
    get_exercise_aliases,
    get_exercise_history,
    get_exercise_pr,
    list_all_exercises,
)
from src.design_system import get_colors
from src.ui_utils import action_button, empty_state, render_page_header


LOAD_RE = re.compile(r"([\d.]+)")


def show():
    """Render the exercise encyclopedia page."""
    render_page_header("Exercise Encyclopedia", "Your full exercise database and history")

    db_path = get_db_path()
    if not os.path.exists(db_path):
        empty_state("", "No Database", "Build your database from the DB Status page first.")
        action_button("DB Status", "database_status", width="stretch")
        return

    conn = get_connection(db_path)
    colors = get_colors()

    try:
        all_exercises = list_all_exercises(conn)
        if not all_exercises:
            empty_state("", "No Exercises", "Sync your workout data to populate the database.")
            action_button("Back to Dashboard", "dashboard", width="stretch")
            return

        # ── Summary metrics ─────────────────────────────────────────
        total = len(all_exercises)
        with_logs = sum(1 for e in all_exercises if e["log_count"] > 0)
        total_logs = sum(e["log_count"] for e in all_exercises)

        c1, c2, c3 = st.columns(3)
        c1.metric("Total Exercises", f"{total}")
        c2.metric("With Log Data", f"{with_logs}")
        c3.metric("Total Log Entries", f"{total_logs:,}")

        st.markdown("---")

        # ── Search and filter ───────────────────────────────────────
        col_search, col_filter = st.columns([3, 1])
        with col_search:
            search = st.text_input(
                "Search exercises",
                placeholder="e.g. bench, curl, squat, rdl...",
                key="enc_search",
            )
        with col_filter:
            sort_by = st.selectbox(
                "Sort by",
                ["Name (A-Z)", "Most logged", "Recently used"],
                key="enc_sort",
            )

        # Filter
        exercises = list(all_exercises)
        if search:
            q = search.lower()
            exercises = [e for e in exercises if q in (e["name"] or "").lower()]

        # Sort
        if sort_by == "Most logged":
            exercises.sort(key=lambda e: e["log_count"], reverse=True)
        elif sort_by == "Recently used":
            exercises.sort(
                key=lambda e: e["last_seen"] or "",
                reverse=True,
            )

        st.caption(f"Showing {len(exercises)} of {total} exercises")

        if not exercises:
            st.info("No exercises match your search.")
            return

        # ── Exercise list ───────────────────────────────────────────
        # Show as selectable list
        exercise_names = [e["name"] for e in exercises]
        exercise_map = {e["name"]: e for e in exercises}

        selected_name = st.selectbox(
            "Select an exercise to view details",
            exercise_names,
            key="enc_select",
        )

        if not selected_name:
            return

        selected = exercise_map[selected_name]
        st.markdown("---")

        # ── Exercise detail card ────────────────────────────────────
        st.markdown(f"## {selected['name']}")

        # Aliases
        aliases = get_exercise_aliases(conn, selected["id"])
        if aliases:
            alias_names = [a["raw_name"] for a in aliases if a["raw_name"] != selected["name"]]
            if alias_names:
                st.markdown(
                    f"<div style='color:{colors['text_secondary']};font-size:0.9rem;margin-bottom:1rem;'>"
                    f"Also known as: {', '.join(alias_names)}</div>",
                    unsafe_allow_html=True,
                )

        # PR and stats
        pr = get_exercise_pr(conn, selected["id"])
        mc1, mc2, mc3, mc4 = st.columns(4)
        mc1.metric("Sessions", f"{selected['log_count']}")
        mc2.metric("First Seen", selected["first_seen"] or "N/A")
        mc3.metric("Last Seen", selected["last_seen"] or "N/A")
        if pr:
            mc4.metric("PR Load", f"{pr['load']} kg")
        else:
            mc4.metric("PR Load", "N/A")

        # ── Load progression chart ──────────────────────────────────
        history = get_exercise_history(conn, selected["id"], limit=50)
        if history:
            chart_points = []
            for i, row in enumerate(reversed(history)):
                load_match = LOAD_RE.search(str(row["prescribed_load"] or ""))
                if load_match:
                    chart_points.append(
                        {
                            "Session": i + 1,
                            "Load (kg)": float(load_match.group(1)),
                        }
                    )

            if len(chart_points) >= 2:
                import pandas as pd

                st.markdown("### Load Progression")
                df = pd.DataFrame(chart_points)
                st.line_chart(df.set_index("Session"))

            # ── Session-by-session history ──────────────────────────
            st.markdown("### Session History")
            for i, row in enumerate(history):
                rx_parts = []
                if row["prescribed_sets"]:
                    rx_parts.append(str(row["prescribed_sets"]))
                if row["prescribed_reps"]:
                    rx_parts.append(str(row["prescribed_reps"]))
                rx = " x ".join(rx_parts)
                if row["prescribed_load"]:
                    rx = f"{rx} @ {row['prescribed_load']}"

                date_str = row["session_date"] or row["day_label"] or "Unknown"
                label = f"**{i + 1}.** {date_str} — {rx}" if rx else f"**{i + 1}.** {date_str}"

                with st.expander(label):
                    pcol, lcol = st.columns(2)
                    with pcol:
                        st.markdown("**Prescribed**")
                        st.write(f"Sets: {row['prescribed_sets'] or 'N/A'}")
                        st.write(f"Reps: {row['prescribed_reps'] or 'N/A'}")
                        st.write(f"Load: {row['prescribed_load'] or 'N/A'}")
                        st.write(f"Rest: {row['prescribed_rest'] or 'N/A'}")
                        if row["prescribed_notes"]:
                            st.write(f"Notes: {row['prescribed_notes']}")
                    with lcol:
                        st.markdown("**Logged**")
                        if row["log_text"]:
                            st.success(row["log_text"])
                        else:
                            st.info("Not logged")
                        if row["parsed_rpe"] is not None:
                            st.write(f"RPE: {row['parsed_rpe']:.1f}")
        else:
            st.info("No log entries yet for this exercise.")

    finally:
        conn.close()

    st.markdown("---")
    action_button("Back to Dashboard", "dashboard", width="stretch")
