"""
Minimal workout logger for testing
"""
import streamlit as st

def show():
    st.title("Workout Logger - Minimal Test")
    st.success("Page loaded successfully!")
    st.write("If you see this, the page is working. Now adding features back...")
    
    if st.button("Back to Dashboard"):
        st.session_state.current_page = 'dashboard'
        st.rerun()
