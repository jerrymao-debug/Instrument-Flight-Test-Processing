from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path


REPO_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(REPO_DIR / "code"))

from pipeline_config import (  # noqa: E402
    CSV_DIR,
    GOOGLE_DRIVE_NCODE_FOLDER_URL,
    NCODE_WORKFLOW_DIR,
    PHASE_SPLIT_DIR,
    PSD_OUTPUT_DIR,
    RAW_NCODE_DIR,
)


NCODE_DIR = NCODE_WORKFLOW_DIR
DRIVE_FOLDER_URL = GOOGLE_DRIVE_NCODE_FOLDER_URL
REQUIRED_WORKFLOWS = ("0_FlightPhaseSplit.flo", "4_FDS_SRS.flo")


def ensure_dirs() -> None:
    for path in (NCODE_DIR, CSV_DIR, RAW_NCODE_DIR, PHASE_SPLIT_DIR, PSD_OUTPUT_DIR):
        path.mkdir(parents=True, exist_ok=True)
    print("Created local processing folders.")


def check_workflows() -> bool:
    missing = [name for name in REQUIRED_WORKFLOWS if not (NCODE_DIR / name).exists()]
    if not missing:
        print("nCode workflow files are present.")
        return True
    print("Missing nCode workflow file(s):")
    for name in missing:
        print(f"  {NCODE_DIR / name}")
    return False


def normalize_downloaded_workflows() -> None:
    for name in REQUIRED_WORKFLOWS:
        target = NCODE_DIR / name
        if target.exists():
            continue
        matches = [path for path in NCODE_DIR.rglob(name) if path.is_file()]
        if matches:
            shutil.copy2(matches[0], target)


def download_workflows() -> bool:
    try:
        import gdown  # noqa: F401
    except ImportError:
        print("gdown is not installed. Run:")
        print("  python -m pip install -r requirements.txt")
        return False

    command = [
        sys.executable,
        "-m",
        "gdown",
        "--folder",
        DRIVE_FOLDER_URL,
        "-O",
        str(NCODE_DIR),
        "--remaining-ok",
    ]
    print("Downloading nCode workflow files from Google Drive...")
    result = subprocess.run(command, cwd=str(REPO_DIR))
    if result.returncode != 0:
        print("Drive download failed. You can download manually from:")
        print(f"  {DRIVE_FOLDER_URL}")
        print(f"Then place the .flo files in: {NCODE_DIR}")
        return False

    normalize_downloaded_workflows()
    return check_workflows()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Prepare the local Instrument Flight Test processing repo.")
    parser.add_argument("--download-ncode", action="store_true", help="Download .flo workflows from Google Drive.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    ensure_dirs()
    if args.download_ncode:
        return 0 if download_workflows() else 1
    check_workflows()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
