from pathlib import Path
from datetime import datetime


class MetadataExtractor:
    """
    Extracts basic metadata from a digital evidence file.
    """

    def extract(self, file_path: str) -> dict:

        path = Path(file_path)

        metadata = {
            "file_name": path.name,
            "extension": path.suffix.lower(),
            "size_bytes": path.stat().st_size,
            "created_time": datetime.fromtimestamp(
                path.stat().st_ctime
            ).isoformat(),
            "modified_time": datetime.fromtimestamp(
                path.stat().st_mtime
            ).isoformat()
        }

        return metadata