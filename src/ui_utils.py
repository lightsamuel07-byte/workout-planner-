"""
UI utility functions for consistent component rendering across pages.
"""

import streamlit as st
import yaml
from src.sheets_reader import SheetsReader


def get_authenticated_reader():
    """
    Factory function to get pre-authenticated SheetsReader with config loaded.

    Returns:
        SheetsReader: Authenticated reader instance
    """
    with open('config.yaml', 'r') as f:
        config = yaml.safe_load(f)

    reader = SheetsReader(
        credentials_file=config['google_sheets']['credentials_file'],
        spreadsheet_id=config['google_sheets']['spreadsheet_id']
    )
    reader.authenticate()
    return reader


def render_page_header(title, subtitle=None, title_icon=""):
    """
    Render standardized page header with title and optional subtitle.

    Args:
        title: Main page title
        subtitle: Optional subtitle text
        title_icon: Optional emoji/icon before title
    """
    icon_text = f"{title_icon} " if title_icon else ""
    st.markdown(
        f'<div class="main-header">{icon_text}{title}</div>',
        unsafe_allow_html=True
    )
    if subtitle:
        st.markdown(
            f'<div class="sub-header">{subtitle}</div>',
            unsafe_allow_html=True
        )


def nav_button(label, page_name, icon="", **kwargs):
    """
    Unified navigation button with automatic session state handling.

    Args:
        label: Button label text
        page_name: Target page identifier
        icon: Optional emoji/icon before label
        **kwargs: Additional Streamlit button parameters

    Returns:
        bool: True if button was clicked
    """
    button_text = f"{icon} {label}".strip() if icon else label
    if st.button(button_text, **kwargs):
        st.session_state.current_page = page_name
        st.rerun()
        return True
    return False
