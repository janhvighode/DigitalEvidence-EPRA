from pathlib import Path
import mimetypes


class EvidenceClassifier:

    EXTENSION_MAP = {
        ".pdf": "PDF",
        ".jpg": "IMAGE",
        ".jpeg": "IMAGE",
        ".png": "IMAGE",
        ".gif": "IMAGE",
        ".bmp": "IMAGE",

        ".mp4": "VIDEO",
        ".avi": "VIDEO",
        ".mkv": "VIDEO",
        ".mov": "VIDEO",

        ".mp3": "AUDIO",
        ".wav": "AUDIO",
        ".aac": "AUDIO",
        ".m4a": "AUDIO",

        ".doc": "DOCUMENT",
        ".docx": "DOCUMENT",
        ".txt": "DOCUMENT",
        ".rtf": "DOCUMENT",

        ".xls": "SPREADSHEET",
        ".xlsx": "SPREADSHEET",
        ".csv": "SPREADSHEET",

        ".zip": "ARCHIVE",
        ".rar": "ARCHIVE",
        ".7z": "ARCHIVE",
        ".tar": "ARCHIVE",
        ".gz": "ARCHIVE"
    }

    @staticmethod
    def classify(file_path: str) -> dict:

        path = Path(file_path)

        if not path.exists():
            raise FileNotFoundError(
                f"File not found: {file_path}"
            )

        if not path.is_file():
            raise ValueError(
                f"Path is not a file: {file_path}"
            )

        extension = path.suffix.lower()

        mime_type, _ = mimetypes.guess_type(path.name)

        evidence_type = EvidenceClassifier.EXTENSION_MAP.get(
            extension,
            "OTHER"
        )

        return {
            "file_name": path.name,
            "extension": extension,
            "mime_type": mime_type or "application/octet-stream",
            "evidence_type": evidence_type
        }