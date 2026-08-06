from pathlib import Path


class EvidenceClassifier:
    """
    Classifies digital evidence based on file properties.
    """

    FILE_TYPES = {

        # Images
        "jpg": "IMAGE",
        "jpeg": "IMAGE",
        "png": "IMAGE",
        "gif": "IMAGE",
        "bmp": "IMAGE",

        # Videos
        "mp4": "VIDEO",
        "avi": "VIDEO",
        "mkv": "VIDEO",
        "mov": "VIDEO",

        # Audio
        "mp3": "AUDIO",
        "wav": "AUDIO",
        "aac": "AUDIO",

        # Documents
        "pdf": "PDF",
        "doc": "DOCUMENT",
        "docx": "DOCUMENT",
        "txt": "DOCUMENT",

        # Emails
        "eml": "EMAIL",
        "msg": "EMAIL",

        # Executables
        "exe": "EXECUTABLE",
        "dll": "EXECUTABLE",
        "bat": "EXECUTABLE",

        # Archives
        "zip": "ARCHIVE",
        "rar": "ARCHIVE",
        "7z": "ARCHIVE",

        # Database
        "db": "DATABASE",
        "sqlite": "DATABASE",

        # Logs
        "log": "LOG"
    }


    def classify(self, file_name: str) -> str:
        """
        Returns evidence type based on file extension.
        """

        extension = Path(file_name).suffix.lower()

        if extension.startswith("."):
            extension = extension[1:]

        return self.FILE_TYPES.get(extension, "UNKNOWN")