#!/bin/bash
# Launch script for the Workout Planning Web App

cd "$(dirname "$0")"

echo "🚀 Launching Workout Planning App..."
echo "📱 The app will open in your default browser"
echo "⏹️  Press Ctrl+C to stop the server"
echo ""

# Add streamlit to PATH if needed
export PATH="/Users/samuellight/Library/Python/3.13/bin:$PATH"

# Run streamlit
streamlit run app.py
