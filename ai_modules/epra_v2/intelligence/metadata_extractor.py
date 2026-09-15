"""
metadata_extractor.py

Extracts metadata from digital evidence files.
"""

from pathlib import Path
from datetime import datetime
import mimetypes
import uuid

from ..models.metadata import Metadata


class MetadataExtractor:
    """
    Extracts metadata from a digital evidence file.
    """

    @staticmethod
    def extract(file_path: str) -> Metadata:

        path = Path(file_path)

        if not path.exists():
            raise FileNotFoundError(
                f"Evidence file not found: {file_path}"
            )

        stat = path.stat()

        mime_type, _ = mimetypes.guess_type(str(path))

        return Metadata(

            # -------------------------
            # Basic File Information
            # -------------------------

            file_name=path.name,

            extension=path.suffix.lower(),

            mime_type=mime_type or "application/octet-stream",

            size=stat.st_size,

            # -------------------------
            # Location
            # -------------------------

            absolute_path=str(path.resolve()),

            parent_directory=str(path.parent),

            # -------------------------
            # Time Information
            # -------------------------

            created_time=datetime.fromtimestamp(stat.st_ctime),

            modified_time=datetime.fromtimestamp(stat.st_mtime),

            accessed_time=datetime.fromtimestamp(stat.st_atime),

            # -------------------------
            # Ownership
            # -------------------------

            owner=str(stat.st_uid)
            if hasattr(stat, "st_uid")
            else "Unknown",

            # -------------------------
            # Investigation
            # -------------------------

            evidence_id=str(uuid.uuid4()),

            evidence_type="UNKNOWN",

            hash_algorithm="SHA-256"
        )