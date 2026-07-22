from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any


CODE_DIR = Path(__file__).resolve().parent
REPO_DIR = CODE_DIR.parent
CONFIG_FILE = REPO_DIR / "config.local.json"


def _load_config() -> dict[str, Any]:
    if not CONFIG_FILE.exists():
        return {}
    with CONFIG_FILE.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def _path_from_config(config: dict[str, Any], key: str, default: Path) -> Path:
    value = os.environ.get(f"IFT_{key.upper()}") or config.get(key)
    if value:
        return Path(str(value)).expanduser()
    return default


CONFIG = _load_config()

BASE_DIR = _path_from_config(CONFIG, "base_dir", REPO_DIR)
PROCESSING_DIR = _path_from_config(CONFIG, "processing_dir", BASE_DIR / "Processing data")
CSV_DIR = _path_from_config(CONFIG, "csv_dir", PROCESSING_DIR / "csv")
RAW_NCODE_DIR = _path_from_config(CONFIG, "raw_ncode_dir", PROCESSING_DIR / "_ncode raw")
PHASE_SPLIT_DIR = _path_from_config(CONFIG, "phase_split_dir", PROCESSING_DIR / "0_phase_split")
PSD_OUTPUT_DIR = _path_from_config(CONFIG, "psd_output_dir", PROCESSING_DIR / "4_psd")

NCODE_WORKFLOW_DIR = _path_from_config(CONFIG, "ncode_workflow_dir", BASE_DIR / "ncode_workflows")
FLIGHT_PHASE_FLOW = _path_from_config(CONFIG, "flight_phase_flow", NCODE_WORKFLOW_DIR / "0_FlightPhaseSplit.flo")
FDS_SRS_FLOW = _path_from_config(CONFIG, "fds_srs_flow", NCODE_WORKFLOW_DIR / "4_FDS_SRS.flo")

ASCII_TRANSLATE_EXE = _path_from_config(
    CONFIG,
    "ascii_translate_exe",
    Path(r"C:\Program Files\nCode\nCode 2025.1 64-bit\GlyphWorks\bin\asciitranslate.exe"),
)
FLOWPROC_EXE = _path_from_config(
    CONFIG,
    "flowproc_exe",
    Path(r"C:\Program Files\nCode\nCode 2025.1 64-bit\GlyphWorks\bin\flowproc.exe"),
)

TS_OUTPUT_GLYPH = str(CONFIG.get("ts_output_glyph", "Loop Flight Phases.SuperGlyph1.TSOutput1"))
TS_INPUT_GLYPH = str(CONFIG.get("ts_input_glyph", "TSInput1"))

DESTINATION_S3_URI = str(
    CONFIG.get("destination_s3_uri", "s3://vibration-data-daq/Instrumented fly test dashboard/")
)
PREFERRED_AWS_PROFILE = str(CONFIG.get("preferred_aws_profile", "ncode-sso"))
GOOGLE_DRIVE_NCODE_FOLDER_URL = str(
    CONFIG.get(
        "google_drive_ncode_folder_url",
        "https://drive.google.com/drive/folders/1A9eKlr5zPrf4V_mc2MZ-89cImgY7aOpi",
    )
)


def ensure_processing_directories() -> None:
    for path in (CSV_DIR, RAW_NCODE_DIR, PHASE_SPLIT_DIR, PSD_OUTPUT_DIR, NCODE_WORKFLOW_DIR):
        path.mkdir(parents=True, exist_ok=True)
