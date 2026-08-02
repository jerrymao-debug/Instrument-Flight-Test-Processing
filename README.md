# Instrument Flight Test Processing

This repo runs the nCode processing pipeline for the Instrument Flight Test dashboard.

It takes raw CSV files, converts them to nCode time-series files, splits them by flight phase, creates TAS/PSD/SRS/FDS/ERS outputs, and uploads the final mission folders to S3 for the dashboard.

## What Is In Git

- `code/final_code.py` runs the full local processing pipeline.
- `code/upload_to_aws.py` uploads finished outputs to S3 and skips files that are already uploaded with the same size.
- `code/refresh_mission_aircraft_map.py` maps mission IDs to aircraft IDs from the Google Sheet.
- `code/refresh_sensor_mission_metadata.py` refreshes dashboard sensor metadata from the Google Sheet.
- `setup_project.py` creates the local folder layout and can download the nCode workflow files.

The large/generated data folders are ignored by Git. The nCode `.flo` workflow files are included in `ncode_workflows\` so a fresh clone can run the same pipeline. The Google Drive folder is still useful as a shared mirror:

https://drive.google.com/drive/folders/1A9eKlr5zPrf4V_mc2MZ-89cImgY7aOpi

## One-Click Windows Start

After downloading or cloning the repository, double-click this file in the repository root:

```text
START-PROCESSING.cmd
```

The launcher performs the complete local workflow:

1. Checks for Python, AWS CLI, nCode, and both required `.flo` workflow files.
2. Shows a Windows pop-up identifying any missing software or file.
3. Creates the `Processing data` folder layout.
4. Installs missing Python packages from `requirements.txt`.
5. Checks for at least one input CSV in `Processing data\csv`.
6. Runs the complete nCode processing pipeline.
7. Opens AWS SSO sign-in when required and uploads the completed results to S3.

The first-time requirements are Python 3, AWS CLI v2, and nCode 2025.1 64-bit. If nCode is missing, the launcher opens the company [ReliaSoft and nCode Installation and Setup](https://flyzipline.atlassian.net/wiki/spaces/REL/pages/1928953995/ReliaSoft+and+nCode+Installation+and+Setup) page. If nCode is installed in a different location, copy `config.example.json` to `config.local.json` and update the two executable paths.

To validate the computer without processing data, run:

```powershell
.\START-PROCESSING.cmd -CheckOnly
```

To process without uploading to AWS, run:

```powershell
.\START-PROCESSING.cmd -SkipUpload
```

## First-Time Setup

Run these commands from the repo root:

```powershell
python -m pip install -r requirements.txt
python setup_project.py --download-ncode
```

The repo already includes these two workflow files. If you want to refresh them from Drive, download these two files manually from the Drive folder and replace the copies in `ncode_workflows\`:

- `0_FlightPhaseSplit.flo`
- `4_FDS_SRS.flo`

Then run:

```powershell
python setup_project.py
```

## Folder Layout

By default the repo uses this local structure:

```text
Processing data/
  csv/            input CSV files go here
  _ncode raw/     generated .s3t raw files
  0_phase_split/  generated phase-split files
  4_psd/          final TAS/PSD/SRS/FDS/ERS outputs
ncode_workflows/
  0_FlightPhaseSplit.flo
  4_FDS_SRS.flo
```

To use a different base folder or a different nCode install path, copy `config.example.json` to `config.local.json` and edit it. `config.local.json` is ignored by Git.

## Run The Pipeline

Put the source CSV files in:

```text
Processing data\csv
```

Run the full pipeline:

```powershell
python code\final_code.py
```

Useful test commands:

```powershell
python code\final_code.py --limit 1
python code\final_code.py --limit 1 --overwrite
python code\final_code.py --skip-translate
python code\final_code.py --skip-split
```

On Windows you can also double-click:

```text
code\run_final_code.bat
```

## Upload To AWS

The upload step reads files from `Processing data\4_psd`, routes each mission into the correct aircraft folder by looking up the mission ID, and uploads to:

```text
s3://vibration-data-daq/Instrumented fly test dashboard/
```

Login first:

```powershell
aws sso login --profile ncode-sso
```

Then upload:

```powershell
python code\upload_to_aws.py --profile ncode-sso
```

The upload script avoids duplicate uploads by checking the destination S3 key and skipping files that already exist with the same size. Use `--force` only when you intentionally want to replace existing remote files:

```powershell
python code\upload_to_aws.py --profile ncode-sso --force
```

Dry run:

```powershell
python code\upload_to_aws.py --profile ncode-sso --dry-run
```

## Google Sheet Metadata

The upload script refreshes `mission_aircraft_map.csv` before upload. It can use public CSV export when available. For private sheet access or future tabs, set `GOOGLE_OAUTH_ACCESS_TOKEN`; then the script discovers every tab whose title contains `Test Data Log`.

```powershell
$env:GOOGLE_OAUTH_ACCESS_TOKEN = "<token>"
python code\refresh_mission_aircraft_map.py
python code\refresh_sensor_mission_metadata.py
```

## Updating nCode Workflows

If the `.flo` files are changed in nCode:

1. Save the updated `.flo` files.
2. Replace the copies in `ncode_workflows\` and commit them to GitHub.
3. Replace the copies in the Google Drive folder if you are keeping the Drive mirror updated.
4. On each processing machine, pull the latest GitHub changes, or run `python setup_project.py --download-ncode` if you are using the Drive mirror.
5. Run `python code\final_code.py --overwrite` when you want to regenerate existing outputs.

## Notes

- nCode 2025.1 64-bit is the default expected install path.
- The CSV to `.s3t` step uses the nCode ASCII Translate UI through `pywinauto`.
- The FDS/SRS/PSD/ERS step uses `flowproc.exe`.
- The dashboard website code lives in the separate dashboard repo; this repo is only the processing and upload side.
