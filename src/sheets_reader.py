"""
Google Sheets integration for reading workout history.
"""

import os
import pickle
from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import InstalledAppFlow
from googleapiclient.discovery import build
from googleapiclient.errors import HttpError

try:
    import streamlit as st
    HAS_STREAMLIT = True
except ImportError:
    HAS_STREAMLIT = False

# If modifying these scopes, delete the file token.json.
SCOPES = ['https://www.googleapis.com/auth/spreadsheets']


class SheetsReader:
    """Handles reading workout history from Google Sheets."""

    def __init__(self, credentials_file, spreadsheet_id, sheet_name="Sheet1"):
        """
        Initialize the Sheets reader.

        Args:
            credentials_file: Path to the Google API credentials JSON file
            spreadsheet_id: The ID of the Google Sheets spreadsheet
            sheet_name: Name of the sheet tab to read from
        """
        self.credentials_file = credentials_file
        self.spreadsheet_id = spreadsheet_id
        self.sheet_name = sheet_name
        self.service = None

    def authenticate(self):
        """Authenticate with Google Sheets API."""
        creds = None

        # Check if running in Streamlit Cloud with service account
        if HAS_STREAMLIT and hasattr(st, 'secrets') and 'gcp_service_account' in st.secrets:
            # Use service account (Streamlit Cloud)
            from google.oauth2 import service_account

            credentials_dict = dict(st.secrets['gcp_service_account'])
            creds = service_account.Credentials.from_service_account_info(
                credentials_dict,
                scopes=SCOPES
            )
            print("✓ Authenticated with service account")
        else:
            # Use local credentials.json file
            # The file token.json stores the user's access and refresh tokens
            if os.path.exists('token.json'):
                creds = Credentials.from_authorized_user_file('token.json', SCOPES)

            # If there are no (valid) credentials available, let the user log in
            if not creds or not creds.valid:
                if creds and creds.expired and creds.refresh_token:
                    creds.refresh(Request())
                else:
                    if not os.path.exists(self.credentials_file):
                        raise FileNotFoundError(
                            f"Credentials file not found: {self.credentials_file}\n"
                            f"Please follow the setup guide in docs/google_sheets_setup.md"
                        )

                    flow = InstalledAppFlow.from_client_secrets_file(
                        self.credentials_file, SCOPES)
                    creds = flow.run_local_server(port=0)

                # Save the credentials for the next run
                with open('token.json', 'w') as token:
                    token.write(creds.to_json())

        self.service = build('sheets', 'v4', credentials=creds)
        print("✓ Successfully authenticated with Google Sheets")

    def read_workout_history(self, num_recent_workouts=20):
        """
        Read recent workout history from the sheet.

        Args:
            num_recent_workouts: Number of recent workouts to retrieve

        Returns:
            List of workout data as dictionaries
        """
        if not self.service:
            raise RuntimeError("Not authenticated. Call authenticate() first.")

        try:
            # Read all data from the sheet
            range_name = f"{self.sheet_name}!A:H"
            result = self.service.spreadsheets().values().get(
                spreadsheetId=self.spreadsheet_id,
                range=range_name
            ).execute()

            values = result.get('values', [])

            if not values:
                print("No data found in sheet.")
                return []

            # Parse the data
            workouts = self._parse_workout_data(values)

            # Return the most recent workouts
            recent_workouts = workouts[-num_recent_workouts:] if len(workouts) > num_recent_workouts else workouts

            print(f"✓ Read {len(recent_workouts)} recent workouts from Google Sheets")
            return recent_workouts

        except HttpError as err:
            print(f"Error reading from Google Sheets: {err}")
            return []

    def _parse_workout_data(self, values):
        """
        Parse raw sheet data into structured workout data.

        Args:
            values: Raw values from Google Sheets

        Returns:
            List of workout dictionaries
        """
        workouts = []
        current_date = None
        current_workout = None

        for row in values:
            if not row:  # Skip empty rows
                continue

            # Check if this is a date row (e.g., "Tuesday 1/20")
            first_col = row[0] if len(row) > 0 else ""

            # Simple heuristic: if first column contains a day name or date pattern
            if any(day in first_col for day in ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]):
                # Save previous workout if exists
                if current_workout:
                    workouts.append(current_workout)

                # Start new workout
                current_date = first_col
                current_workout = {
                    'date': current_date,
                    'exercises': []
                }
                continue

            # Check if this is a header row
            if first_col.lower() in ['block', 'rationale']:
                continue

            # This is an exercise row
            if current_workout and len(row) >= 2:
                exercise = {
                    'block': row[0] if len(row) > 0 else '',
                    'exercise': row[1] if len(row) > 1 else '',
                    'sets': row[2] if len(row) > 2 else '',
                    'reps': row[3] if len(row) > 3 else '',
                    'load': row[4] if len(row) > 4 else '',
                    'rest': row[5] if len(row) > 5 else '',
                    'notes': row[6] if len(row) > 6 else '',
                    'log': row[7] if len(row) > 7 else ''
                }

                # Only add if it's not a header or empty
                if exercise['exercise'] and exercise['exercise'].lower() != 'exercise':
                    current_workout['exercises'].append(exercise)

        # Add the last workout
        if current_workout:
            workouts.append(current_workout)

        return workouts

    def format_history_for_ai(self, workouts):
        """
        Format workout history in a clean way for AI consumption.

        Args:
            workouts: List of workout dictionaries

        Returns:
            Formatted string of workout history
        """
        if not workouts:
            return "No workout history available."

        formatted = "RECENT WORKOUT HISTORY:\n\n"

        for workout in workouts:
            formatted += f"=== {workout['date']} ===\n"

            # Group exercises by block
            blocks = {}
            for exercise in workout['exercises']:
                block = exercise['block'] or 'Other'
                if block not in blocks:
                    blocks[block] = []
                blocks[block].append(exercise)

            # Format each block
            for block_name, exercises in blocks.items():
                formatted += f"\n{block_name}:\n"
                for ex in exercises:
                    formatted += f"  - {ex['exercise']}"
                    if ex['sets']:
                        formatted += f" | {ex['sets']} sets"
                    if ex['reps']:
                        formatted += f" x {ex['reps']} reps"
                    if ex['load']:
                        formatted += f" @ {ex['load']}"
                    if ex['notes']:
                        formatted += f" | Notes: {ex['notes']}"
                    formatted += "\n"

            formatted += "\n"

        return formatted

    def find_most_recent_weekly_plan(self):
        """
        Find the most recent 'Weekly Plan' sheet in the spreadsheet.

        Returns:
            Sheet name of the most recent weekly plan, or None if not found
        """
        if not self.service:
            raise RuntimeError("Not authenticated. Call authenticate() first.")

        try:
            # Get all sheets in the spreadsheet
            sheet_metadata = self.service.spreadsheets().get(
                spreadsheetId=self.spreadsheet_id
            ).execute()

            sheets = sheet_metadata.get('sheets', [])
            sheet_names = [sheet['properties']['title'] for sheet in sheets]

            # Filter for sheets that match "Weekly Plan (M/D/YYYY)" or "(Weekly Plan) M/D/YYYY" pattern
            import re
            from datetime import datetime

            weekly_plan_sheets = []
            # Try both patterns
            pattern1 = r'Weekly Plan \((\d+)/(\d+)/(\d+)\)'  # New format
            pattern2 = r'\(Weekly Plan\)\s*(\d+)/(\d+)/(\d+)'  # Old format

            for name in sheet_names:
                match = re.match(pattern1, name) or re.match(pattern2, name)
                if match:
                    month, day, year = int(match.group(1)), int(match.group(2)), int(match.group(3))
                    try:
                        date = datetime(year, month, day)
                        weekly_plan_sheets.append((name, date))
                    except ValueError:
                        continue

            if not weekly_plan_sheets:
                return None

            # Sort by date and get the most recent
            weekly_plan_sheets.sort(key=lambda x: x[1], reverse=True)
            most_recent_sheet = weekly_plan_sheets[0][0]

            print(f"✓ Found most recent weekly plan: {most_recent_sheet}")
            return most_recent_sheet

        except HttpError as err:
            print(f"Error finding weekly plan sheets: {err}")
            return None

    def read_prior_week_supplemental(self):
        """
        Read the supplemental workouts (Tue/Thu/Sat) from the most recent Weekly Plan sheet.

        Returns:
            Dictionary with Tuesday, Thursday, Saturday workouts and logged data
        """
        sheet_name = self.find_most_recent_weekly_plan()

        if not sheet_name:
            print("No prior weekly plan found.")
            return None

        if not self.service:
            raise RuntimeError("Not authenticated. Call authenticate() first.")

        try:
            # Read all data from the weekly plan sheet
            range_name = f"'{sheet_name}'!A:H"
            result = self.service.spreadsheets().values().get(
                spreadsheetId=self.spreadsheet_id,
                range=range_name
            ).execute()

            values = result.get('values', [])

            if not values:
                print(f"No data found in {sheet_name}")
                return None

            # Parse supplemental days (Tuesday, Thursday, Saturday)
            supplemental_data = self._parse_supplemental_workouts(values)

            print(f"✓ Read prior week's supplemental workouts from {sheet_name}")
            return supplemental_data

        except HttpError as err:
            print(f"Error reading prior week's plan: {err}")
            return None

    def _parse_supplemental_workouts(self, values):
        """
        Parse supplemental workouts (Tue/Thu/Sat) from Weekly Plan sheet.

        Args:
            values: Raw values from the sheet

        Returns:
            Dictionary with Tuesday, Thursday, Saturday workout data
        """
        supplemental_data = {
            'Tuesday': [],
            'Thursday': [],
            'Saturday': []
        }

        current_day = None
        in_exercise_section = False

        for i, row in enumerate(values):
            if not row:
                continue

            first_col = row[0] if len(row) > 0 else ""

            # Detect day headers
            if 'TUESDAY' in first_col.upper() or 'THURSDAY' in first_col.upper() or 'SATURDAY' in first_col.upper():
                if 'TUESDAY' in first_col.upper():
                    current_day = 'Tuesday'
                elif 'THURSDAY' in first_col.upper():
                    current_day = 'Thursday'
                elif 'SATURDAY' in first_col.upper():
                    current_day = 'Saturday'
                else:
                    current_day = None
                in_exercise_section = False
                continue

            # Detect column headers (Block, Exercise, Sets, etc.)
            if first_col.lower() == 'block' and current_day:
                in_exercise_section = True
                continue

            # Parse exercise rows
            if in_exercise_section and current_day and len(row) >= 2:
                exercise_data = {
                    'block': row[0] if len(row) > 0 else '',
                    'exercise': row[1] if len(row) > 1 else '',
                    'sets': row[2] if len(row) > 2 else '',
                    'reps': row[3] if len(row) > 3 else '',
                    'load': row[4] if len(row) > 4 else '',
                    'rest': row[5] if len(row) > 5 else '',
                    'notes': row[6] if len(row) > 6 else '',
                    'log': row[7] if len(row) > 7 else ''
                }

                # Only add if it has an exercise name
                if exercise_data['exercise'] and exercise_data['exercise'].lower() != 'exercise':
                    supplemental_data[current_day].append(exercise_data)

        return supplemental_data

    def get_all_weekly_plan_sheets(self):
        """
        Get ALL weekly plan sheet names sorted by date (not just most recent).

        Returns:
            List of sheet names in chronological order
        """
        if not self.service:
            raise RuntimeError("Not authenticated. Call authenticate() first.")

        try:
            # Get all sheets in the spreadsheet
            sheet_metadata = self.service.spreadsheets().get(
                spreadsheetId=self.spreadsheet_id
            ).execute()

            sheets = sheet_metadata.get('sheets', [])
            sheet_names = [sheet['properties']['title'] for sheet in sheets]

            # Filter for weekly plan sheets
            import re
            from datetime import datetime

            weekly_plan_sheets = []
            pattern1 = r'Weekly Plan \((\d+)/(\d+)/(\d+)\)'
            pattern2 = r'\(Weekly Plan\)\s*(\d+)/(\d+)/(\d+)'

            for name in sheet_names:
                match = re.match(pattern1, name) or re.match(pattern2, name)
                if match:
                    month, day, year = int(match.group(1)), int(match.group(2)), int(match.group(3))
                    try:
                        date = datetime(year, month, day)
                        weekly_plan_sheets.append((name, date))
                    except ValueError:
                        continue

            # Sort by date
            weekly_plan_sheets.sort(key=lambda x: x[1])

            # Return just the names
            return [name for name, date in weekly_plan_sheets]

        except HttpError as err:
            print(f"Error getting weekly plan sheets: {err}")
            return []

    def format_supplemental_for_ai(self, supplemental_data):
        """
        Format prior week's supplemental workouts for AI prompt.

        Args:
            supplemental_data: Dictionary with Tuesday, Thursday, Saturday data

        Returns:
            Formatted string for AI
        """
        if not supplemental_data:
            return "No prior week supplemental data available."

        formatted = "PRIOR WEEK'S SUPPLEMENTAL WORKOUTS (Tue/Thu/Sat):\n\n"

        for day in ['Tuesday', 'Thursday', 'Saturday']:
            exercises = supplemental_data.get(day, [])
            if not exercises:
                continue

            formatted += f"=== {day.upper()} ===\n"

            for ex in exercises:
                formatted += f"  {ex['block']} - {ex['exercise']}"
                if ex['sets'] and ex['reps']:
                    formatted += f" | {ex['sets']} x {ex['reps']}"
                if ex['load']:
                    formatted += f" @ {ex['load']} kg"
                if ex['log']:
                    formatted += f" | LOGGED: {ex['log']}"
                elif ex['notes']:
                    formatted += f" | {ex['notes']}"
                formatted += "\n"

            formatted += "\n"

        return formatted
