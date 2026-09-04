import mimetypes
from pathlib import Path
from datetime import datetime


class MetadataService:

    @staticmethod
    def extract_metadata(file_path: str) -> dict:
        """
        Extract technical metadata from an evidence file.
        """

        path = Path(file_path)

        if not path.exists():
            raise FileNotFoundError(f"File not found: {file_path}")

        if not path.is_file():
            raise ValueError(f"Path is not a file: {file_path}")

        stat = path.stat()

        mime_type, _ = mimetypes.guess_type(path.name)

        return {
            "file_name": path.name,
            "file_extension": path.suffix.lower(),
            "file_size_bytes": stat.st_size,
            "file_size_kb": round(stat.st_size / 1024, 2),
            "mime_type": mime_type or "application/octet-stream",
            "created_at": datetime.fromtimestamp(
                stat.st_ctime
            ).isoformat(),
            "modified_at": datetime.fromtimestamp(
                stat.st_mtime
            ).isoformat()
        }