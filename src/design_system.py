"""
Design system constants and reusable component functions.
Conservative animations, teal/mint accent, mobile-first.
"""

import streamlit as st

# Color tokens
COLORS = {
    'primary': '#000000',
    'primary_variant': '#1A1A1A',
    'accent': '#00D4AA',
    'accent_dark': '#00B894',
    'background': '#FAFAFA',
    'surface': '#FFFFFF',
    'success': '#00D4AA',
    'warning': '#FF6B35',
    'error': '#DC3545',
    'info': '#3B82F6',
    'text_primary': '#000000',
    'text_secondary': '#6B7280',
    'text_disabled': '#9CA3AF',
    'border_strong': '#000000',
    'border_medium': '#D1D5DB',
    'border_light': '#E5E7EB',
}

# Dark mode colors
COLORS_DARK = {
    'primary': '#FFFFFF',
    'primary_variant': '#E5E5E5',
    'accent': '#00D4AA',
    'accent_dark': '#00B894',
    'background': '#0F0F0F',
    'surface': '#1A1A1A',
    'success': '#00D4AA',
    'warning': '#FF6B35',
    'error': '#DC3545',
    'info': '#3B82F6',
    'text_primary': '#FFFFFF',
    'text_secondary': '#9CA3AF',
    'text_disabled': '#6B7280',
    'border_strong': '#FFFFFF',
    'border_medium': '#374151',
    'border_light': '#1F2937',
}


def get_colors():
    """Get current color scheme based on dark mode setting"""
    dark_mode = st.session_state.get('dark_mode', False)
    return COLORS_DARK if dark_mode else COLORS


def get_metric_card_html(label, value, delta=None, icon="", color_scheme=None):
    """Enhanced metric card with accent color highlights"""
    if color_scheme is None:
        color_scheme = get_colors()
    
    delta_html = ""
    if delta:
        delta_color = color_scheme['success'] if isinstance(delta, str) and delta.startswith('+') else color_scheme['text_secondary']
        delta_html = f'<div style="font-size: 0.875rem; color: {delta_color}; margin-top: 0.25rem;">{delta}</div>'
    
    return f"""
    <div style="
        background: {color_scheme['surface']};
        border: 2px solid {color_scheme['border_light']};
        padding: 1rem;
        border-radius: 8px;
        transition: transform 150ms cubic-bezier(0.4, 0, 0.2, 1), box-shadow 150ms cubic-bezier(0.4, 0, 0.2, 1);
    " class="metric-card">
        <div style="display: flex; align-items: center; gap: 0.5rem; margin-bottom: 0.5rem;">
            {f'<span style="font-size: 1.25rem;">{icon}</span>' if icon else ''}
            <div style="font-size: 0.75rem; text-transform: uppercase; font-weight: 700; color: {color_scheme['text_secondary']}; letter-spacing: 0.05em;">{label}</div>
        </div>
        <div style="font-size: 1.875rem; font-weight: 700; color: {color_scheme['text_primary']};">{value}</div>
        {delta_html}
    </div>
    """


def get_empty_state_html(icon, title, description, color_scheme=None):
    """Consistent empty state component"""
    if color_scheme is None:
        color_scheme = get_colors()
    
    return f"""
    <div style="
        text-align: center;
        padding: 3rem 2rem;
        background: {color_scheme['surface']};
        border: 2px solid {color_scheme['border_light']};
        border-radius: 12px;
        margin: 2rem 0;
    ">
        <div style="font-size: 4rem; margin-bottom: 1rem;">{icon}</div>
        <div style="font-size: 1.25rem; font-weight: 600; margin-bottom: 0.5rem; color: {color_scheme['text_primary']};">{title}</div>
        <div style="color: {color_scheme['text_secondary']}; line-height: 1.5;">{description}</div>
    </div>
    """


def get_loading_skeleton_html(height="100px", width="100%", color_scheme=None):
    """Loading skeleton with shimmer effect"""
    if color_scheme is None:
        color_scheme = get_colors()
    
    return f"""
    <div style="
        height: {height};
        width: {width};
        background: linear-gradient(
            90deg,
            {color_scheme['border_light']} 25%,
            {color_scheme['border_medium']} 50%,
            {color_scheme['border_light']} 75%
        );
        background-size: 200% 100%;
        animation: shimmer 1.5s infinite;
        border-radius: 8px;
    " class="skeleton"></div>
    """


def get_progress_bar_html(current, total, show_percentage=True, color_scheme=None):
    """Progress bar component"""
    if color_scheme is None:
        color_scheme = get_colors()
    
    percentage = (current / total * 100) if total > 0 else 0
    percentage_text = f"{percentage:.0f}%" if show_percentage else ""
    
    return f"""
    <div style="margin: 1rem 0;">
        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 0.5rem;">
            <span style="font-size: 0.875rem; font-weight: 600; color: {color_scheme['text_primary']};">{current} / {total} Complete</span>
            <span style="font-size: 0.875rem; font-weight: 600; color: {color_scheme['accent']};">{percentage_text}</span>
        </div>
        <div style="
            width: 100%;
            height: 8px;
            background: {color_scheme['border_light']};
            border-radius: 4px;
            overflow: hidden;
        ">
            <div style="
                width: {percentage}%;
                height: 100%;
                background: {color_scheme['accent']};
                transition: width 250ms cubic-bezier(0.4, 0, 0.2, 1);
            "></div>
        </div>
    </div>
    """


def get_stat_grid_html(stats, columns=4, color_scheme=None):
    """Grid layout for stats"""
    if color_scheme is None:
        color_scheme = get_colors()
    
    stats_html = ""
    for stat in stats:
        label = stat.get('label', '')
        value = stat.get('value', '')
        stats_html += f"""
        <div style="
            border: 2px solid {color_scheme['border_strong']};
            padding: 0.75rem;
            background: {color_scheme['surface']};
        ">
            <div style="font-size: 0.7rem; text-transform: uppercase; font-weight: 700; color: {color_scheme['text_secondary']};">{label}</div>
            <div style="font-weight: 700; color: {color_scheme['text_primary']}; font-size: 1.2rem; margin-top: 0.25rem;">{value}</div>
        </div>
        """
    
    return f"""
    <div style="
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(120px, 1fr));
        gap: 0.5rem;
        margin: 0.75rem 0;
    ">
        {stats_html}
    </div>
    """


def get_completion_badge_html(completed=False, color_scheme=None):
    """Small completion badge"""
    if color_scheme is None:
        color_scheme = get_colors()
    
    if completed:
        return f'<span style="color: {color_scheme["success"]}; font-size: 1.25rem;">✓</span>'
    else:
        return f'<span style="color: {color_scheme["border_medium"]}; font-size: 1.25rem;">○</span>'


def get_accent_button_style(color_scheme=None):
    """Get CSS for accent button"""
    if color_scheme is None:
        color_scheme = get_colors()
    
    return f"""
    background-color: {color_scheme['accent']} !important;
    color: {color_scheme['primary']} !important;
    border: 2px solid {color_scheme['accent']} !important;
    font-weight: 600 !important;
    """
