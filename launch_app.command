#!/bin/bash

# Sam's Workout App Launcher
# Double-click this file to start the app

cd "$(dirname "$0")"

echo "🏋️  Starting Sam's Workout App..."
echo ""

# Set API key from .env file
export ANTHROPIC_API_KEY=$(grep ANTHROPIC_API_KEY .env | cut -d '=' -f2)

# Start Streamlit in the background
python3 -m streamlit run app.py &

# Wait for server to start
echo "⏳ Waiting for server to start..."
sleep 3

# Open browser
echo "🌐 Opening app in browser..."
open http://localhost:8501

echo ""
echo "✅ App is running!"
echo "💡 To stop the app, close this terminal window or press Ctrl+C"
echo ""

# Keep terminal open
wait
