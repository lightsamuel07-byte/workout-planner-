"""
Writes workout plans to Google Sheets.
"""

from googleapiclient.discovery import build
from google.oauth2.credentials import Credentials
import os
import re
from datetime import datetime

try:
    import streamlit as st
    HAS_STREAMLIT = True
except ImportError:
    HAS_STREAMLIT = False

SCOPES = ['https://www.googleapis.com/auth/spreadsheets']


class SheetsWriter:
    """Handles writing workout plans to Google Sheets."""

    def __init__(self, credentials_file, spreadsheet_id, sheet_name='Weekly Plan'):
        """
        Initialize the SheetsWriter.

        Args:
            credentials_file: Path to Google credentials JSON
            spreadsheet_id: ID of the Google Sheets spreadsheet
            sheet_name: Name of the sheet to write to (default: 'Weekly Plan')
        """
        self.credentials_file = credentials_file
        self.spreadsheet_id = spreadsheet_id
        self.sheet_name = sheet_name
        self.service = None

    def authenticate(self):
        """
        Authenticate with Google Sheets API.
        Supports both local token.json and Streamlit Cloud service accounts.
        """
        creds = None

        # Check if running in Streamlit Cloud with service account
        use_service_account = False
        if HAS_STREAMLIT and hasattr(st, 'secrets'):
            try:
                if 'gcp_service_account' in st.secrets:
                    use_service_account = True
            except (AttributeError, KeyError):
                pass

        if use_service_account:
            # Use service account (Streamlit Cloud)
            from google.oauth2 import service_account

            credentials_dict = dict(st.secrets['gcp_service_account'])
            creds = service_account.Credentials.from_service_account_info(
                credentials_dict,
                scopes=SCOPES
            )
        else:
            # Use local token.json
            if not os.path.exists('token.json'):
                raise Exception("token.json not found. Please run authentication first.")
            creds = Credentials.from_authorized_user_file('token.json', SCOPES)

        self.service = build('sheets', 'v4', credentials=creds)

    def write_workout_plan(self, plan_text):
        """
        Write the workout plan to Google Sheets.

        Args:
            plan_text: The generated workout plan as markdown text

        Returns:
            True if successful, False otherwise
        """
        if not self.service:
            raise Exception("Not authenticated. Call authenticate() first.")

        # Parse the plan into structured data
        rows = self._parse_plan_to_rows(plan_text)

        # Check if sheet exists, create if not
        self._ensure_sheet_exists()

        # Clear existing content
        self._clear_sheet()

        # Write the new plan
        self._write_rows(rows)

        return True

    def archive_sheet_if_exists(self, archived_sheet_name):
        """Rename the current sheet to an archived name if it exists."""
        if not self.service:
            raise Exception("Not authenticated. Call authenticate() first.")

        sheet_id = self._get_sheet_id_by_title(self.sheet_name)
        if sheet_id is None:
            return False

        request_body = {
            'requests': [
                {
                    'updateSheetProperties': {
                        'properties': {
                            'sheetId': sheet_id,
                            'title': archived_sheet_name
                        },
                        'fields': 'title'
                    }
                }
            ]
        }
        self.service.spreadsheets().batchUpdate(
            spreadsheetId=self.spreadsheet_id,
            body=request_body
        ).execute()

        return True

    def _parse_plan_to_rows(self, plan_text):
        """
        Parse the markdown plan into structured rows for Google Sheets.
        NOW handles a single unified format for all exercises.
        """
        rows = []

        # Add title with timestamp
        timestamp = datetime.now().strftime('%B %d, %Y at %I:%M %p')
        rows.append([f'Workout Plan - Generated {timestamp}'])
        rows.append([])

        lines = plan_text.split('\n')
        current_day = ""
        i = 0

        while i < len(lines):
            line = lines[i].rstrip()

            # Detect day headers (## MONDAY, ## TUESDAY, etc.)
            if line.startswith('## ') and any(day in line.upper() for day in
                ['MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY', 'SATURDAY', 'SUNDAY']):
                if current_day:
                    rows.append([])

                current_day = line.replace('## ', '').strip()
                rows.append([current_day])
                rows.append([])
                rows.append(['Block', 'Exercise', 'Sets', 'Reps', 'Load (kg)', 'Rest', 'Notes', 'Log'])
                i += 1
                continue

            # Parse exercises in unified format: ### A1. Exercise Name
            if line.startswith('### ') and current_day:
                exercise_line = line.replace('### ', '').strip()

                # Check if it matches the pattern: A1. Exercise or B2. Exercise, etc.
                if '. ' in exercise_line:
                    parts = exercise_line.split('. ', 1)
                    block_label = parts[0].strip()
                    exercise_name = parts[1].strip() if len(parts) > 1 else ""

                    # Validate block label (A1, B2, C3, etc.)
                    if re.match(r'^[A-Z]\d+$', block_label):
                        # Extract exercise details from following bullet points (8-column format)
                        sets, reps, load, rest, notes = self._extract_exercise_details(lines, i + 1)
                        rows.append([block_label, exercise_name, sets, reps, load, rest, notes, ''])

            i += 1

        return rows

    def _extract_exercise_details(self, lines, start_idx):
        """
        Extract sets, reps, load, rest, and notes from bullet points after an exercise header.
        Simplified 8-column format:
        - 3 x 12 @ 20 kg
        - **Rest:** 60s
        - **Notes:** Coaching cues, technique points, intensity targets all in one field
        """
        sets = ""
        reps = ""
        load = ""
        rest = ""
        notes = ""

        i = start_idx
        while i < len(lines):
            line = lines[i].strip()

            # Stop at next exercise header or day header
            if line.startswith('###') or line.startswith('##') or line.startswith('---'):
                break

            # Skip empty lines
            if not line:
                i += 1
                continue

            # Parse bullet points
            if line.startswith('- ') or line.startswith('* '):
                content = line[2:].strip()

                # First bullet typically has sets x reps @ load
                if ' x ' in content and not sets:
                    # Extract sets
                    sets_match = re.search(r'^(\d+)\s*x', content)
                    if sets_match:
                        sets = sets_match.group(1)

                    # Extract reps (can be single number or time like "1:00")
                    reps_match = re.search(r'x\s*([\d:]+)', content)
                    if reps_match:
                        reps = reps_match.group(1)

                    # Extract load
                    load_match = re.search(r'@\s*([\d\.]+)', content)
                    if load_match:
                        load = load_match.group(1)

                # Parse rest
                elif content.startswith('**Rest:**'):
                    rest = content.replace('**Rest:**', '').strip()

                # Parse notes (all coaching info goes here now)
                elif content.startswith('**Notes:**'):
                    notes = content.replace('**Notes:**', '').strip()

                # Catch additional note lines (continuation without ** prefix)
                elif notes and not content.startswith('**'):
                    notes += ' ' + content

            i += 1

        return sets, reps, load, rest, notes

    def _ensure_sheet_exists(self):
        """Check if the sheet exists, create it if not."""
        try:
            sheet_metadata = self.service.spreadsheets().get(
                spreadsheetId=self.spreadsheet_id
            ).execute()

            sheets = sheet_metadata.get('sheets', [])
            sheet_names = [sheet['properties']['title'] for sheet in sheets]

            if self.sheet_name not in sheet_names:
                request_body = {
                    'requests': [{
                        'addSheet': {
                            'properties': {
                                'title': self.sheet_name
                            }
                        }
                    }]
                }
                self.service.spreadsheets().batchUpdate(
                    spreadsheetId=self.spreadsheet_id,
                    body=request_body
                ).execute()
                print(f"Created new sheet: '{self.sheet_name}'")

        except Exception as e:
            print(f"Error ensuring sheet exists: {e}")
            raise

    def _get_sheet_id_by_title(self, title):
        try:
            sheet_metadata = self.service.spreadsheets().get(
                spreadsheetId=self.spreadsheet_id
            ).execute()

            for sheet in sheet_metadata.get('sheets', []):
                props = sheet.get('properties', {})
                if props.get('title') == title:
                    return props.get('sheetId')

            return None
        except Exception as e:
            print(f"Error getting sheet id: {e}")
            raise

    def _clear_sheet(self):
        """Clear all content from the sheet."""
        try:
            range_name = f"{self.sheet_name}!A1:Z1000"
            self.service.spreadsheets().values().clear(
                spreadsheetId=self.spreadsheet_id,
                range=range_name
            ).execute()
        except Exception as e:
            print(f"Error clearing sheet: {e}")
            raise

    def _write_rows(self, rows):
        """Write rows to the sheet."""
        try:
            range_name = f"{self.sheet_name}!A1"
            body = {
                'values': rows
            }
            self.service.spreadsheets().values().update(
                spreadsheetId=self.spreadsheet_id,
                range=range_name,
                valueInputOption='RAW',
                body=body
            ).execute()

            print(f"\n✓ Workout plan written to Google Sheets!")
            print(f"  Sheet: '{self.sheet_name}'")
            print(f"  Rows written: {len(rows)}")

        except Exception as e:
            print(f"Error writing to sheet: {e}")
            raise
