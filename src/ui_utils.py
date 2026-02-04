"""
UI utility functions for consistent component rendering across pages.
"""

import streamlit as st
import yaml
from src.sheets_reader import SheetsReader
from src.design_system import (
    get_colors,
    get_metric_card_html,
    get_empty_state_html,
    get_loading_skeleton_html,
    get_progress_bar_html,
    get_stat_grid_html,
    get_completion_badge_html
)


def with_loading(message="Loading..."):
    """
    Decorator/context manager for showing loading state during operations
    
    Usage as context manager:
        with with_loading("Fetching workout data..."):
            data = fetch_data()
    """
    class LoadingContext:
        def __init__(self, msg):
            self.message = msg
            self.spinner = None
            
        def __enter__(self):
            self.spinner = st.spinner(self.message)
            self.spinner.__enter__()
            return self
            
        def __exit__(self, *args):
            if self.spinner:
                self.spinner.__exit__(*args)
    
    return LoadingContext(message)


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
        spreadsheet_id=config['google_sheets']['spreadsheet_id'],
        service_account_file=config.get('google_sheets', {}).get('service_account_file')
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


def metric_card(label, value, delta=None, icon=""):
    """
    Render enhanced metric card using design system.
    
    Args:
        label: Metric label
        value: Metric value
        delta: Optional delta/change indicator
        icon: Optional emoji icon
    """
    colors = get_colors()
    html = get_metric_card_html(label, value, delta, icon, colors)
    st.markdown(html, unsafe_allow_html=True)


def empty_state(icon, title, description):
    """
    Render consistent empty state component.
    
    Args:
        icon: Emoji icon
        title: Empty state title
        description: Empty state description
    """
    colors = get_colors()
    html = get_empty_state_html(icon, title, description, colors)
    st.markdown(html, unsafe_allow_html=True)


def loading_skeleton(height="100px", width="100%"):
    """
    Render loading skeleton with shimmer effect.
    
    Args:
        height: Skeleton height
        width: Skeleton width
    """
    colors = get_colors()
    html = get_loading_skeleton_html(height, width, colors)
    st.markdown(html, unsafe_allow_html=True)


def progress_bar(current, total, show_percentage=True):
    """
    Render progress bar component.
    
    Args:
        current: Current progress value
        total: Total value
        show_percentage: Whether to show percentage
    """
    colors = get_colors()
    html = get_progress_bar_html(current, total, show_percentage, colors)
    st.markdown(html, unsafe_allow_html=True)


def stat_grid(stats, columns=4):
    """
    Render grid layout for stats.
    
    Args:
        stats: List of dicts with 'label' and 'value' keys
        columns: Number of columns in grid
    """
    colors = get_colors()
    html = get_stat_grid_html(stats, columns, colors)
    st.markdown(html, unsafe_allow_html=True)


def completion_badge(completed=False):
    """
    Render small completion badge.
    
    Args:
        completed: Whether item is completed
    
    Returns:
        str: HTML for badge
    """
    colors = get_colors()
    return get_completion_badge_html(completed, colors)


def action_button(label, page_name, icon="", accent=False, **kwargs):
    """
    Enhanced action button with optional accent styling.
    
    Args:
        label: Button label
        page_name: Target page
        icon: Optional icon
        accent: Whether to use accent color
        **kwargs: Additional button parameters
    """
    button_text = f"{icon} {label}".strip() if icon else label
    
    if accent and 'type' not in kwargs:
        kwargs['type'] = 'primary'
    
    if st.button(button_text, **kwargs):
        st.session_state.current_page = page_name
        st.rerun()
        return True
    return False
