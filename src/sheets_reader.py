"""
Google Sheets integration for reading workout history.
"""

import os
import pickle
import json
import re
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
RPE_VALUE_RE = re.compile(r"\brpe\s*[:=]?\s*(\d+(?:\.\d+)?)\b", re.IGNORECASE)


class SheetsReader:
    """Handles reading workout history from Google Sheets."""

    def __init__(
        self,
        credentials_file,
        spreadsheet_id,
        sheet_name="Sheet1",
        service_account_file=None
    ):
        """
        Initialize the Sheets reader.

        Args:
            credentials_file: Path to the Google API credentials JSON file
            spreadsheet_id: The ID of the Google Sheets spreadsheet
            sheet_name: Name of the sheet tab to read from
            service_account_file: Optional path to service account JSON for headless auth
        """
        self.credentials_file = credentials_file
        self.spreadsheet_id = spreadsheet_id
        self.sheet_name = sheet_name
        self.service_account_file = service_account_file
        self.service = None

    def authenticate(self):
        """Authenticate with Google Sheets API."""
        creds = None

        # Check if running in Streamlit Cloud with service account
        use_service_account = False
        if HAS_STREAMLIT and hasattr(st, 'secrets'):
            try:
                if 'gcp_service_account' in st.secrets:
                    use_service_account = True
            except (AttributeError, KeyError):
                pass  # Secrets not available, use local credentials

        service_account_file = self._service_account_file_to_use()

        if use_service_account:
            # Use service account (Streamlit Cloud)
            from google.oauth2 import service_account

            credentials_dict = dict(st.secrets['gcp_service_account'])
            creds = service_account.Credentials.from_service_account_info(
                credentials_dict,
                scopes=SCOPES
            )
            print("✓ Authenticated with service account")
        elif service_account_file:
            # Use service account file (local/headless)
            creds = self._load_service_account_file(service_account_file)
            print("✓ Authenticated with service account file")
        elif os.getenv('GOOGLE_SERVICE_ACCOUNT_JSON'):
            # Use service account JSON from environment variable
            creds = self._load_service_account_env_json(os.getenv('GOOGLE_SERVICE_ACCOUNT_JSON'))
            print("✓ Authenticated with service account JSON from environment")
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

    def _service_account_file_to_use(self):
        """
        Resolve which service account file (if any) should be used.
        Priority:
        1) Explicit constructor arg
        2) GOOGLE_SERVICE_ACCOUNT_FILE env var
        3) credentials_file, if it is a service account JSON
        """
        if self.service_account_file:
            return self.service_account_file

        env_service_file = os.getenv('GOOGLE_SERVICE_ACCOUNT_FILE')
        if env_service_file:
            return env_service_file

        if self._is_service_account_json_file(self.credentials_file):
            return self.credentials_file

        return None

    def _is_service_account_json_file(self, path):
        """Check if path is a service account credentials file."""
        if not path or not os.path.exists(path):
            return False

        try:
            with open(path, 'r', encoding='utf-8') as f:
                payload = json.load(f)
            return payload.get('type') == 'service_account'
        except (OSError, json.JSONDecodeError):
            return False

    def _load_service_account_file(self, path):
        """Load service account credentials from a JSON file."""
        if not os.path.exists(path):
            raise FileNotFoundError(f"Service account file not found: {path}")

        from google.oauth2 import service_account

        return service_account.Credentials.from_service_account_file(
            path,
            scopes=SCOPES
        )

    def _load_service_account_env_json(self, json_str):
        """Load service account credentials from an env JSON string."""
        try:
            payload = json.loads(json_str)
        except json.JSONDecodeError as exc:
            raise ValueError("GOOGLE_SERVICE_ACCOUNT_JSON is not valid JSON") from exc

        if payload.get('type') != 'service_account':
            raise ValueError("GOOGLE_SERVICE_ACCOUNT_JSON must be a service account payload")

        from google.oauth2 import service_account

        return service_account.Credentials.from_service_account_info(
            payload,
            scopes=SCOPES
        )

    def read_workout_history(self, num_recent_workouts=7, use_cache=True):
        """
        Read workout history from Google Sheets with optional caching.
        
        Args:
            num_recent_workouts: Number of recent workouts to return (default 7 for weekly view)
            use_cache: Whether to use cached data if available (default True)
            
        Returns:
            List of workout data as dictionaries
        """
        if not self.service:
            raise RuntimeError("Not authenticated. Call authenticate() first.")

        try:
            # Read all data from the sheet
            # 8-column schema: Block, Exercise, Sets, Reps, Load, Rest, Notes, Log (A:H = 8 columns)
            range_name = f"{self.sheet_name}!A:H"
            print(f"[READ DEBUG] Reading from sheet: '{self.sheet_name}'")
            print(f"[READ DEBUG] Range: {range_name}")
            
            result = self.service.spreadsheets().values().get(
                spreadsheetId=self.spreadsheet_id,
                range=range_name
            ).execute()

            values = result.get('values', [])
            
            # Debug: Show first 5 rows
            print(f"[READ DEBUG] Total rows: {len(values)}")
            if values:
                for i, row in enumerate(values[:5]):
                    print(f"[READ DEBUG] Row {i} length={len(row)}: {row[:min(9, len(row))]}")

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

            # Check if this is a date row (e.g., "Tuesday 1/20" or "TUESDAY - AESTHETICS")
            first_col = row[0] if len(row) > 0 else ""

            # Simple heuristic: if first column contains a day name or date pattern (case-insensitive)
            if any(day.lower() in first_col.lower() for day in ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]):
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
                # Debug first exercise of first workout
                if len(current_workout['exercises']) == 0 and current_workout.get('date', '').startswith('MONDAY'):
                    print(f"[PARSE DEBUG] First Monday exercise row length: {len(row)}")
                    print(f"[PARSE DEBUG] Row data: {row[:min(8, len(row))]}")
                    print(f"[PARSE DEBUG] Column H (row[7]): '{row[7] if len(row) > 7 else 'OUT OF RANGE'}'")

                # 8-column schema: A=Block, B=Exercise, C=Sets, D=Reps, E=Load, F=Rest, G=Notes, H=Log
                exercise = {
                    'block': row[0] if len(row) > 0 else '',
                    'exercise': row[1] if len(row) > 1 else '',
                    'sets': row[2] if len(row) > 2 else '',
                    'reps': row[3] if len(row) > 3 else '',
                    'load': row[4] if len(row) > 4 else '',
                    'rest': row[5] if len(row) > 5 else '',
                    'notes': row[6] if len(row) > 6 else '',    # Column G
                    'log': row[7] if len(row) > 7 else ''       # Column H is the LOG column
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

        return self.read_supplemental_from_sheet(sheet_name)

    def read_supplemental_from_sheet(self, sheet_name):
        """
        Read supplemental workouts (Tue/Thu/Sat) from a specific sheet.

        Args:
            sheet_name: Exact Google Sheet tab name

        Returns:
            Dictionary with Tuesday, Thursday, Saturday workout data
        """
        if not sheet_name:
            return None

        if not self.service:
            raise RuntimeError("Not authenticated. Call authenticate() first.")

        try:
            # Read all data from the weekly plan sheet
            # 8-column schema: Block, Exercise, Sets, Reps, Load, Rest, Notes, Log (A:H = 8 columns)
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

            print(f"✓ Read supplemental workouts from {sheet_name}")
            return supplemental_data

        except HttpError as err:
            print(f"Error reading supplemental workouts from {sheet_name}: {err}")
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
                # 8-column schema: A=Block, B=Exercise, C=Sets, D=Reps, E=Load, F=Rest, G=Notes, H=Log
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
                    parsed_rpe = self._extract_rpe_from_text(ex['log'])
                    if parsed_rpe is not None:
                        formatted += f" | RPE_PARSED: {parsed_rpe:.1f}"
                elif ex['notes']:
                    formatted += f" | {ex['notes']}"
                formatted += "\n"

            formatted += "\n"

        return formatted

    def read_generation_summary(self, sheet_name):
        """
        Read AI generation summary block from a weekly plan sheet.

        Returns:
            dict with keys {'validation': str, 'explanation_lines': list[str]}
            or None when block is absent.
        """
        if not sheet_name:
            return None

        if not self.service:
            raise RuntimeError("Not authenticated. Call authenticate() first.")

        try:
            range_name = f"'{sheet_name}'!A:H"
            result = self.service.spreadsheets().values().get(
                spreadsheetId=self.spreadsheet_id,
                range=range_name
            ).execute()
            values = result.get('values', [])
            if not values:
                return None

            start_idx = None
            for idx, row in enumerate(values):
                if len(row) > 0 and str(row[0]).strip() == "AI Generation Summary":
                    start_idx = idx
                    break

            if start_idx is None:
                return None

            summary = {"validation": "", "explanation_lines": []}
            in_explanation = False
            for row in values[start_idx + 1:]:
                col_a = str(row[0]).strip() if len(row) > 0 else ""
                col_g = str(row[6]).strip() if len(row) > 6 else ""
                if not col_a and not col_g:
                    continue

                if col_a == "Validation":
                    summary["validation"] = col_g
                    in_explanation = False
                    continue

                if col_a == "Explanation":
                    in_explanation = True
                    continue

                if in_explanation and col_g:
                    summary["explanation_lines"].append(col_g)

            if not summary["validation"] and not summary["explanation_lines"]:
                return None
            return summary
        except HttpError as err:
            print(f"Error reading generation summary from {sheet_name}: {err}")
            return None

    def _extract_rpe_from_text(self, text):
        """Parse explicit numeric RPE value from freeform log text."""
        if not text:
            return None

        match = RPE_VALUE_RE.search(text)
        if not match:
            return None

        value = float(match.group(1))
        if 1.0 <= value <= 10.0:
            return value
        return None

    def write_workout_logs(self, workout_date, logs):
        """
        Write workout logs back to Google Sheets.

        Args:
            workout_date: The date/day identifier for the workout (e.g., "Monday, Jan 20")
            logs: List of dictionaries with 'exercise' and 'log' keys

        Returns:
            Boolean indicating success
        """
        if not self.service:
            raise RuntimeError("Not authenticated. Call authenticate() first.")

        try:
            # Read current sheet data to find the correct rows
            # 8-column schema: Block, Exercise, Sets, Reps, Load, Rest, Notes, Log (A:H = 8 columns)
            range_name = f"'{self.sheet_name}'!A:H"
            result = self.service.spreadsheets().values().get(
                spreadsheetId=self.spreadsheet_id,
                range=range_name
            ).execute()

            values = result.get('values', [])

            if not values:
                print(f"No data found in {self.sheet_name}")
                return False

            # Find the workout date section
            date_row = None
            for i, row in enumerate(values):
                if len(row) > 0 and workout_date in row[0]:
                    date_row = i
                    break

            if date_row is None:
                print(f"Could not find workout date: {workout_date}")
                return False

            # Build update data
            updates = []

            # Start checking rows after the date row
            current_row = date_row + 1
            log_index = 0

            while current_row < len(values) and log_index < len(logs):
                row = values[current_row]

                # Stop if we hit another date header or empty row
                if len(row) == 0 or (len(row) > 0 and any(day in row[0] for day in ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'])):
                    break

                # Check if this row has an exercise name matching our log
                if len(row) > 1:
                    exercise_name = row[1].strip() if len(row) > 1 else ""

                    # Match with our log
                    if log_index < len(logs):
                        log_entry = logs[log_index]

                        # Check if exercise names match (allow partial match)
                        if log_entry['exercise'].lower() in exercise_name.lower() or exercise_name.lower() in log_entry['exercise'].lower():
                            # Column H is the LOG column (8-column schema)
                            # Schema: A=Block, B=Exercise, C=Sets, D=Reps, E=Load, F=Rest, G=Notes, H=Log
                            if log_entry['log']:  # Only update if there's actual log data
                                cell_range = f"'{self.sheet_name}'!H{current_row + 1}"
                                updates.append({
                                    'range': cell_range,
                                    'values': [[log_entry['log']]]
                                })

                            log_index += 1

                current_row += 1

            # Perform batch update
            if updates:
                body = {
                    'valueInputOption': 'USER_ENTERED',
                    'data': updates
                }

                self.service.spreadsheets().values().batchUpdate(
                    spreadsheetId=self.spreadsheet_id,
                    body=body
                ).execute()

                print(f"✓ Updated {len(updates)} exercise logs")
                return True
            else:
                print("No logs to update")
                return False

        except HttpError as err:
            print(f"Error writing workout logs: {err}")
            return False
