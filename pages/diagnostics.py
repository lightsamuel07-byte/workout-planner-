"""
Diagnostics page - Debug connection and data issues
"""

import streamlit as st
import yaml
import os


def show():
    """Render the diagnostics page"""

    st.markdown('<div class="main-header">Diagnostics</div>', unsafe_allow_html=True)
    st.markdown('<div class="sub-header">System status and connection tests</div>', unsafe_allow_html=True)

    st.markdown("---")

    # Check 1: Environment
    st.markdown("### Environment")

    col1, col2 = st.columns(2)
    with col1:
        st.write("**Python Path:**")
        st.code(os.getcwd())

    with col2:
        st.write("**Streamlit Version:**")
        st.code(st.__version__)

    st.markdown("---")

    # Check 2: Secrets availability
    st.markdown("### Secrets & Credentials")

    try:
        has_anthropic = 'ANTHROPIC_API_KEY' in st.secrets
        st.write(f"Anthropic API Key: {'Found' if has_anthropic else 'Missing'}")
    except Exception:
        st.write("Anthropic API Key: Cannot access secrets")

    try:
        has_gcp = 'gcp_service_account' in st.secrets
        st.write(f"GCP Service Account: {'Found' if has_gcp else 'Missing'}")

        if has_gcp:
            # Show some non-sensitive fields
            gcp_keys = list(st.secrets['gcp_service_account'].keys())
            st.write(f"   Keys available: {', '.join(gcp_keys)}")
    except Exception:
        st.write("GCP Service Account: Cannot access secrets")

    st.markdown("---")

    # Check 3: Config file
    st.markdown("### Config File")

    try:
        with open('config.yaml', 'r') as f:
            config = yaml.safe_load(f)

        st.write("Config file loaded successfully")
        st.write(f"   Spreadsheet ID: {config['google_sheets']['spreadsheet_id'][:20]}...")
        st.write(f"   Default sheet: {config['google_sheets']['sheet_name']}")
    except Exception as e:
        st.write(f"Config file error: {e}")

    st.markdown("---")

    # Check 4: Google Sheets connection
    st.markdown("### Google Sheets Connection")

    if st.button("Test Connection", type="primary"):
        with st.spinner("Testing connection..."):
            try:
                from src.sheets_reader import SheetsReader

                with open('config.yaml', 'r') as f:
                    config = yaml.safe_load(f)

                reader = SheetsReader(
                    credentials_file=config['google_sheets']['credentials_file'],
                    spreadsheet_id=config['google_sheets']['spreadsheet_id'],
                    service_account_file=config.get('google_sheets', {}).get('service_account_file')
                )

                st.write("Authenticating...")
                reader.authenticate()
                st.write("Authentication successful!")

                st.write("Fetching sheet names...")
                all_sheets = reader.get_all_weekly_plan_sheets()

                st.write(f"Found {len(all_sheets)} weekly plan sheets:")
                for sheet in all_sheets:
                    st.write(f"   - {sheet}")

                if all_sheets:
                    st.write("Testing data read from most recent sheet...")
                    reader.sheet_name = all_sheets[-1]
                    week_data = reader.read_workout_history()

                    if week_data:
                        st.write(f"Successfully read {len(week_data)} workout days")
                        for workout in week_data:
                            st.write(f"   - {workout.get('date', 'Unknown')}: {len(workout.get('exercises', []))} exercises")
                    else:
                        st.warning("Sheet exists but no workout data found")

            except Exception as e:
                st.error(f"Connection test failed: {e}")
                import traceback
                with st.expander("Error Details"):
                    st.code(traceback.format_exc())

    st.markdown("---")

    # Check 5: Output directory
    st.markdown("### Output Directory")

    output_dir = "output"
    if os.path.exists(output_dir):
        md_files = [f for f in os.listdir(output_dir) if f.endswith('.md')]
        st.write("Output directory exists")
        st.write(f"   Markdown files: {len(md_files)}")
        if md_files:
            for f in md_files:
                st.write(f"   - {f}")
    else:
        st.write("Output directory not found")

    st.markdown("---")

    if st.button("Back to Dashboard", width="stretch"):
        st.session_state.current_page = 'dashboard'
        st.rerun()
