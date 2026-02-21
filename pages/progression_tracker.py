"""
Progression Tracker page - Visual load and volume trends for key exercises.
"""

import os

import pandas as pd
import streamlit as st

from src.db_queries import (
    get_connection,
    get_db_path,
    get_load_progression,
    get_top_exercises_by_volume,
    list_all_exercises,
)
from src.design_system import get_colors
from src.ui_utils import action_button, empty_state, render_page_header


def show():
    """Render the progression tracker page."""
    render_page_header("Progression Tracker", "Track load and volume trends over time")

    db_path = get_db_path()
    if not os.path.exists(db_path):
        empty_state("", "No Database", "Build your database from the DB Status page first.")
        action_button("DB Status", "database_status", width="stretch")
        return

    conn = get_connection(db_path)
    colors = get_colors()

    try:
        all_exercises = list_all_exercises(conn)
        exercises_with_data = [e for e in all_exercises if e["log_count"] >= 2]

        if not exercises_with_data:
            empty_state(
                "",
                "Not Enough Data",
                "Need at least 2 sessions per exercise to show trends. Keep logging!",
            )
            action_button("Back to Dashboard", "dashboard", width="stretch")
            return

        # ── Top movers section ──────────────────────────────────────
        st.markdown("### Most Tracked Exercises")
        top = get_top_exercises_by_volume(conn, limit=8)
        if top:
            cols = st.columns(min(4, len(top)))
            for i, ex in enumerate(top[:4]):
                with cols[i]:
                    st.metric(
                        ex["name"],
                        f"{ex['log_count']} sessions",
                        f"Last: {ex['last_seen'] or 'N/A'}",
                    )

        st.markdown("---")

        # ── Exercise selector ───────────────────────────────────────
        st.markdown("### Detailed Progression")

        col_select, col_metric = st.columns([3, 1])
        with col_select:
            exercise_names = [e["name"] for e in exercises_with_data]
            selected_name = st.selectbox(
                "Select exercise",
                exercise_names,
                key="pt_exercise",
            )
        with col_metric:
            chart_metric = st.selectbox(
                "Chart metric",
                ["Load (kg)", "Volume (sets x reps x load)", "RPE"],
                key="pt_metric",
            )

        if not selected_name:
            return

        selected = next(e for e in exercises_with_data if e["name"] == selected_name)
        progression = get_load_progression(conn, selected["id"], limit=40)

        if len(progression) < 2:
            st.info(f"Not enough data points for {selected_name} yet.")
            return

        # ── Summary stats ───────────────────────────────────────────
        loads = [p["load"] for p in progression]
        first_load = loads[0]
        last_load = loads[-1]
        max_load = max(loads)
        change = last_load - first_load
        change_pct = (change / first_load * 100) if first_load else 0

        sc1, sc2, sc3, sc4 = st.columns(4)
        sc1.metric("Starting Load", f"{first_load} kg")
        sc2.metric("Current Load", f"{last_load} kg")
        sc3.metric(
            "Change",
            f"{change:+.1f} kg",
            f"{change_pct:+.1f}%",
        )
        sc4.metric("All-Time Max", f"{max_load} kg")

        # ── Chart ───────────────────────────────────────────────────
        if chart_metric == "Load (kg)":
            df = pd.DataFrame(
                {
                    "Date": [p["date"] for p in progression],
                    "Load (kg)": [p["load"] for p in progression],
                }
            )
            st.line_chart(df.set_index("Date"))

        elif chart_metric == "Volume (sets x reps x load)":
            df = pd.DataFrame(
                {
                    "Date": [p["date"] for p in progression],
                    "Volume": [p["volume"] for p in progression],
                }
            )
            st.line_chart(df.set_index("Date"))

        elif chart_metric == "RPE":
            rpe_data = [p for p in progression if p["rpe"] is not None]
            if len(rpe_data) >= 2:
                df = pd.DataFrame(
                    {
                        "Date": [p["date"] for p in rpe_data],
                        "RPE": [p["rpe"] for p in rpe_data],
                    }
                )
                st.line_chart(df.set_index("Date"))
            else:
                st.info("Not enough RPE data to chart. Keep logging RPE values!")

        # ── Data table ──────────────────────────────────────────────
        st.markdown("### Raw Data")
        table_data = []
        for p in reversed(progression):
            table_data.append(
                {
                    "Date": p["date"],
                    "Sets": p["sets"] or "-",
                    "Reps": p["reps"] or "-",
                    "Load (kg)": p["load"],
                    "Volume": p["volume"],
                    "RPE": f"{p['rpe']:.1f}" if p["rpe"] is not None else "-",
                }
            )

        st.dataframe(table_data, hide_index=True, width=None)

        # ── Multi-exercise comparison ───────────────────────────────
        st.markdown("---")
        st.markdown("### Compare Exercises")

        compare_names = st.multiselect(
            "Select exercises to compare",
            exercise_names,
            default=[selected_name],
            max_selections=5,
            key="pt_compare",
        )

        if len(compare_names) >= 2:
            compare_data = {}
            for name in compare_names:
                ex = next(e for e in exercises_with_data if e["name"] == name)
                prog = get_load_progression(conn, ex["id"], limit=40)
                if prog:
                    for p in prog:
                        date = p["date"]
                        if date not in compare_data:
                            compare_data[date] = {}
                        compare_data[date][name] = p["load"]

            if compare_data:
                dates = sorted(compare_data.keys())
                chart_df = pd.DataFrame(
                    {name: [compare_data.get(d, {}).get(name) for d in dates] for name in compare_names},
                    index=dates,
                )
                st.line_chart(chart_df)
            else:
                st.info("No overlapping data for comparison.")

    finally:
        conn.close()

    st.markdown("---")
    action_button("Back to Dashboard", "dashboard", width="stretch")
