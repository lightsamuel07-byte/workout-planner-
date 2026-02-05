"""
Design system constants and reusable component functions.
Apple-inspired neutral palette, minimal motion, mobile-first.
"""

import streamlit as st
import html

# Color tokens
COLORS = {
    'primary': '#111111',
    'primary_variant': '#1D1D1F',
    'accent': '#0071E3',
    'accent_dark': '#0066CC',
    'background': '#F5F5F7',
    'surface': '#FFFFFF',
    'success': '#34C759',
    'warning': '#FF9F0A',
    'error': '#FF3B30',
    'info': '#0071E3',
    'text_primary': '#111111',
    'text_secondary': '#6E6E73',
    'text_disabled': '#A1A1A6',
    'border_strong': '#1D1D1F',
    'border_medium': '#D2D2D7',
    'border_light': '#E5E5EA',
}

# Dark mode colors
COLORS_DARK = {
    'primary': '#FFFFFF',
    'primary_variant': '#E5E5E5',
    'accent': '#0A84FF',
    'accent_dark': '#006EDB',
    'background': '#0B0B0C',
    'surface': '#1C1C1E',
    'success': '#30D158',
    'warning': '#FF9F0A',
    'error': '#FF453A',
    'info': '#0A84FF',
    'text_primary': '#F5F5F7',
    'text_secondary': '#8E8E93',
    'text_disabled': '#636366',
    'border_strong': '#F5F5F7',
    'border_medium': '#2C2C2E',
    'border_light': '#3A3A3C',
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
        border: 1px solid {color_scheme['border_medium']};
        padding: 1rem;
        border-radius: 10px;
        transition: box-shadow 120ms ease-out, border-color 120ms ease-out;
    " class="metric-card">
        <div style="display: flex; align-items: center; gap: 0.5rem; margin-bottom: 0.5rem;">
            {f'<span style="font-size: 1.25rem;">{icon}</span>' if icon else ''}
            <div style="font-size: 0.75rem; text-transform: uppercase; font-weight: 700; color: {color_scheme['text_secondary']}; letter-spacing: 0.05em;">{label}</div>
        </div>
        <div style="font-size: 1.875rem; font-weight: 700; color: {color_scheme['text_primary']};">{value}</div>
        {delta_html}
    </div>
    """.strip()


def get_empty_state_html(icon, title, description, color_scheme=None):
    """Consistent empty state component"""
    if color_scheme is None:
        color_scheme = get_colors()
    
    icon_block = ""
    if icon:
        icon_block = f'<div style="font-size: 3rem; margin-bottom: 1rem;">{icon}</div>'

    return f"""
    <div style="
        text-align: center;
        padding: 3rem 2rem;
        background: {color_scheme['surface']};
        border: 1px solid {color_scheme['border_medium']};
        border-radius: 16px;
        margin: 2rem 0;
    ">
        {icon_block}
        <div style="font-size: 1.25rem; font-weight: 600; margin-bottom: 0.5rem; color: {color_scheme['text_primary']};">{title}</div>
        <div style="color: {color_scheme['text_secondary']}; line-height: 1.5;">{description}</div>
    </div>
    """.strip()


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
        border-radius: 10px;
    " class="skeleton"></div>
    """.strip()


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
                transition: width 180ms ease-out;
            "></div>
        </div>
    </div>
    """.strip()


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
            border: 1px solid {color_scheme['border_medium']};
            padding: 0.75rem;
            background: {color_scheme['surface']};
            border-radius: 10px;
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
    """.strip()


def get_completion_badge_html(completed=False, color_scheme=None):
    """Small completion badge"""
    if color_scheme is None:
        color_scheme = get_colors()
    
    if completed:
        return f'<span style="color: {color_scheme["text_secondary"]}; font-size: 1.1rem;">✓</span>'
    else:
        return f'<span style="color: {color_scheme["border_medium"]}; font-size: 1.1rem;">○</span>'


def get_accent_button_style(color_scheme=None):
    """Get CSS for accent button"""
    if color_scheme is None:
        color_scheme = get_colors()
    
    return f"""
    background-color: {color_scheme['accent']} !important;
    color: #FFFFFF !important;
    border: 1px solid {color_scheme['accent']} !important;
    font-weight: 500 !important;
    """


def get_day_card_html(
    day_label,
    date_label,
    emoji,
    title,
    subtitle,
    is_today=False,
    is_completed=False,
    color_scheme=None,
):
    """Weekly schedule day card used by dashboard-style views."""
    if color_scheme is None:
        color_scheme = get_colors()

    border_color = color_scheme['accent'] if is_today else color_scheme['border_medium']
    border_width = '2px' if is_today else '1px'
    box_shadow = '0 2px 6px rgba(0, 113, 227, 0.16)' if is_today else '0 1px 2px rgba(0,0,0,0.06)'
    card_class = "day-card today" if is_today else "day-card"
    completion_icon = get_completion_badge_html(is_completed, color_scheme)

    safe_day_label = html.escape(str(day_label))
    safe_date_label = html.escape(str(date_label))
    emoji_text = str(emoji).strip()
    safe_emoji = html.escape(emoji_text)
    safe_title = html.escape(str(title))
    safe_subtitle = html.escape(str(subtitle))

    emoji_block = ""
    if safe_emoji:
        emoji_block = f'<div style="font-size: 2rem; margin-bottom: 0.5rem;">{safe_emoji}</div>'

    return f"""<div class="{card_class}" style="
        background: {color_scheme['surface']};
        border: {border_width} solid {border_color};
        border-radius: 10px;
        padding: 0.75rem 0.5rem;
        text-align: center;
        min-height: 116px;
        transition: box-shadow 120ms ease-out, border-color 120ms ease-out;
        box-shadow: {box_shadow};
    ">
        <div style="
            font-size: 0.7rem;
            font-weight: 700;
            color: {color_scheme['text_secondary']};
            text-transform: uppercase;
            letter-spacing: 0.5px;
            margin-bottom: 0.25rem;
        ">{safe_day_label}</div>
        <div style="
            font-size: 0.7rem;
            color: {color_scheme['text_secondary']};
            margin-bottom: 0.5rem;
        ">{safe_date_label}</div>
        {emoji_block}
        <div style="
            font-size: 0.85rem;
            font-weight: 600;
            color: {color_scheme['text_primary']};
            margin-bottom: 0.2rem;
        ">{safe_title}</div>
        <div style="
            font-size: 0.7rem;
            color: {color_scheme['text_secondary']};
        ">{safe_subtitle}</div>
        <div style="margin-top: 0.45rem;">{completion_icon}</div>
    </div>""".strip()
