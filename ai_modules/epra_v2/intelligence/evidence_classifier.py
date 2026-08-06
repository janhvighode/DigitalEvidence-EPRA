"""
evidence_classifier.py

Classifies digital evidence based on file extension.

This module is responsible only for determining
the evidence type.
"""

from pathlib import Path


class EvidenceClassifier:
    """
    Classifies evidence according to its file extension.
    """

    IMAGE_EXTENSIONS = {
        ".jpg",
        ".jpeg",
        ".png",
        ".bmp",
        ".gif",
        ".tiff",
        ".webp"
    }

    VIDEO_EXTENSIONS = {
        ".mp4",
        ".avi",
        ".mov",
        ".mkv",
        ".wmv",
        ".flv"
    }

    AUDIO_EXTENSIONS = {
        ".mp3",
        ".wav",
        ".aac",
        ".flac",
        ".ogg"
    }

    PDF_EXTENSIONS = {
        ".pdf"
    }

    DOCUMENT_EXTENSIONS = {
        ".doc",
        ".docx",
        ".txt",
        ".rtf",
        ".odt"
    }

    SPREADSHEET_EXTENSIONS = {
        ".xls",
        ".xlsx",
        ".csv"
    }

    EMAIL_EXTENSIONS = {
        ".eml",
        ".msg",
        ".pst",
        ".ost"
    }

    EXECUTABLE_EXTENSIONS = {
        ".exe",
        ".dll",
        ".bat",
        ".msi",
        ".com"
    }

    DATABASE_EXTENSIONS = {
        ".db",
        ".sqlite",
        ".sqlite3",
        ".mdb",
        ".accdb"
    }

    LOG_EXTENSIONS = {
        ".log"
    }

    ARCHIVE_EXTENSIONS = {
        ".zip",
        ".rar",
        ".7z",
        ".tar",
        ".gz"
    }

    @classmethod
    def classify(cls, file_name: str) -> str:
        """
        Determine the evidence type based on file extension.

        Parameters
        ----------
        file_name : str

        Returns
        -------
        str
            Evidence type.
        """

        extension = Path(file_name).suffix.lower()

        if extension in cls.IMAGE_EXTENSIONS:
            return "IMAGE"

        if extension in cls.VIDEO_EXTENSIONS:
            return "VIDEO"

        if extension in cls.AUDIO_EXTENSIONS:
            return "AUDIO"

        if extension in cls.PDF_EXTENSIONS:
            return "PDF"

        if extension in cls.DOCUMENT_EXTENSIONS:
            return "DOCUMENT"

        if extension in cls.SPREADSHEET_EXTENSIONS:
            return "SPREADSHEET"

        if extension in cls.EMAIL_EXTENSIONS:
            return "EMAIL"

        if extension in cls.EXECUTABLE_EXTENSIONS:
            return "EXECUTABLE"

        if extension in cls.DATABASE_EXTENSIONS:
            return "DATABASE"

        if extension in cls.LOG_EXTENSIONS:
            return "LOG"

        if extension in cls.ARCHIVE_EXTENSIONS:
            return "ARCHIVE"

        return "UNKNOWN"

    @classmethod
    def process(cls, evidence):
        """
        Classifies the evidence and updates
        the metadata with evidence type.
        """

        evidence.metadata.evidence_type = cls.classify(
            evidence.metadata.file_name
        )

        return evidence
    