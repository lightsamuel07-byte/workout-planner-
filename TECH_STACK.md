# TECH_STACK

Last updated: 2026-02-05

## 1. Runtime and Platform

- Language: Python
- Local runtime observed: Python 3.13 (`__pycache__` artifacts)
- Minimum version check in setup script: Python 3.7+
- Web framework: Streamlit
- Local launch command: `streamlit run app.py`

## 2. Pinned Python Dependencies

From `requirements.txt`:
- `streamlit==1.53.1`
- `anthropic==0.76.0`
- `google-api-python-client==2.154.0`
- `google-auth-httplib2==0.2.0`
- `google-auth-oauthlib==1.2.1`
- `PyYAML==6.0.2`
- `python-dotenv==1.2.1`

## 3. Application Layers

- Frontend: Streamlit pages (`app.py`, `pages/*.py`)
- UI shared layer: `src/design_system.py`, `src/ui_utils.py`, `assets/styles.css`
- AI layer: Anthropic Claude via `src/plan_generator.py`
- Data connectors: Google Sheets via `src/sheets_reader.py` and `src/sheets_writer.py`
- Local persistence: SQLite via `src/workout_db.py`
- Analytics: `src/analytics.py`

## 4. Data Stores

- Google Sheets (primary source of weekly plans and daily logs)
- SQLite (`data/workout_history.db`) for normalized local history and trend context
- Local markdown output (`output/workout_plan_*.md`)

## 5. Authentication and Secrets

Supported auth strategies for Google Sheets:
- OAuth token flow with `credentials.json` + `token.json`
- Service account JSON file (`service_account_file` in config or env)
- Streamlit Cloud secrets (`gcp_service_account`)

Anthropic API key sources:
- Environment (`ANTHROPIC_API_KEY` from `.env`)
- Streamlit secrets (`ANTHROPIC_API_KEY`)

App access control:
- Streamlit secret `APP_PASSWORD`

## 6. Configuration Surface

Primary config file: `config.yaml`
- Google Sheets settings
- Claude model and token limits
- Output settings
- Database path
- Athlete profile, goals, and hard training rules

Secondary config files:
- `.streamlit/config.toml`
- `.streamlit/secrets.toml` (local, ignored)
- `.streamlit/secrets.toml.template`

## 7. Entry Points and Scripts

- Web app: `app.py`
- CLI generator: `main.py`
- App launcher: `run_app.sh`
- DB import: `scripts/import_google_sheets_history.py`
- Setup tests: `test_setup.py`, `test_sheets_connection.py`, `test_sheets_writer.py`

## 8. Deployment Assumptions in Current Code

- Streamlit Cloud compatibility is built in (service-account secret path).
- Local desktop workflow remains first-class (OAuth and file-based outputs).
- No dedicated backend service or container orchestration is currently defined.
