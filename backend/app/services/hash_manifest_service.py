import re
import json
from pathlib import Path
from datetime import datetime, timezone
from typing import Dict, Any

from app.database import MANIFEST_DIR

SAFE_ID_REGEX = re.compile(r"^[a-zA-Z0-9_\-]+$")


def validate_safe_id(identifier: str, field_name: str = "ID") -> str:
    """
    Validate that an identifier contains only safe alphanumeric, dash, and underscore characters.
    Prevents path traversal and glob injection.
    """
    if not identifier or not isinstance(identifier, str):
        raise ValueError(f"{field_name} must be a non-empty string.")
    cleaned = identifier.strip()
    if not SAFE_ID_REGEX.match(cleaned):
        raise ValueError(f"Invalid {field_name}: '{identifier}'. Must contain only letters, numbers, hyphens, and underscores.")
    return cleaned


class HashManifestService:

    @staticmethod
    def create_manifest(
        case_id: str,
        evidence_records: list
    ) -> dict:
        """
        Create a structured hash manifest for digital evidence files.
        """
        clean_case_id = validate_safe_id(case_id, "case_id")

        manifest = {
            "case_id": clean_case_id,
            "manifest_type": "Digital Evidence Hash Manifest",
            "hash_algorithm": "SHA-256",
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "total_evidence_files": len(evidence_records),
            "evidence": evidence_records
        }
        return manifest

    @staticmethod
    def save_manifest(
        manifest: dict,
        output_directory: Path = None
    ) -> str:
        """
        Save hash manifest as a JSON file.
        Uses microsecond timestamp and unique suffix to prevent same-second overwrites.
        Enforces path containment within output directory.
        """
        if output_directory is None:
            import app.database as database
            directory = database.MANIFEST_DIR
        else:
            directory = Path(output_directory)

        directory.mkdir(parents=True, exist_ok=True)
        resolved_dir = directory.resolve()

        raw_case_id = manifest.get("case_id", "UNKNOWN_CASE")
        clean_case_id = validate_safe_id(raw_case_id, "case_id")

        now_utc = datetime.now(timezone.utc)
        # Microsecond timestamp ensures uniqueness even under rapid concurrent calls
        timestamp_str = now_utc.strftime("%Y%m%d_%H%M%S_%f")

        file_name = f"{clean_case_id}_hash_manifest_{timestamp_str}.json"
        target_path = (directory / file_name).resolve()

        # Enforce path containment
        if not target_path.is_relative_to(resolved_dir):
            raise ValueError("Target manifest path escapes safe manifest directory.")

        with open(target_path, "w", encoding="utf-8") as file:
            json.dump(manifest, file, indent=4)

        return str(target_path)

    @staticmethod
    def get_latest_manifest(case_id: str, directory: Path = None) -> Path:
        """
        Find the latest manifest for a case, validating case_id and enforcing containment.
        """
        if directory is None:
            import app.database as database
            directory = database.MANIFEST_DIR
        resolved_dir = directory.resolve()

        clean_case_id = validate_safe_id(case_id, "case_id")

        pattern = f"{clean_case_id}_hash_manifest_*.json"
        manifest_files = list(directory.glob(pattern))

        if not manifest_files:
            raise FileNotFoundError(f"No hash manifest found for case: {clean_case_id}")

        # Pick latest by modification time
        latest = max(manifest_files, key=lambda f: f.stat().st_mtime).resolve()

        if not latest.is_relative_to(resolved_dir):
            raise PermissionError("Manifest file resolution outside safe storage directory.")

        return latest