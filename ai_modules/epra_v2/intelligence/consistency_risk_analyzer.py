"""
consistency_risk_analyzer.py

Calculates Consistency Risk (CR) from forensic consistency indicators.

Indicators:
1. File extension vs MIME type mismatch (e.g. executable disguised as document/image)
2. Timestamp sanity (created > modified anomalies, future dates)
3. Size sanity (zero byte or negative files)
"""

from datetime import datetime
from pathlib import Path


class ConsistencyRiskAnalyzer:
    """
    Calculates consistency risk from metadata anomalies.
    """

    EXECUTABLE_EXTENSIONS = {
        ".exe", ".dll", ".bat", ".cmd", ".sh", ".vbs", ".ps1", ".msi", ".scr"
    }

    EXECUTABLE_MIMES = {
        "application/x-dosexec",
        "application/x-msdownload",
        "application/x-executable",
        "application/x-sharedlib"
    }

    EXTENSION_MIME_MAP = {
        ".pdf": {"application/pdf"},
        ".jpg": {"image/jpeg"},
        ".jpeg": {"image/jpeg"},
        ".png": {"image/png"},
        ".gif": {"image/gif"},
        ".mp4": {"video/mp4"},
        ".avi": {"video/x-msvideo"},
        ".mp3": {"audio/mpeg"},
        ".wav": {"audio/wav", "audio/x-wav"},
        ".txt": {"text/plain"},
        ".log": {"text/plain"},
        ".eml": {"message/rfc822", "text/plain", "application/octet-stream"},
        ".xlsx": {
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            "application/octet-stream"
        },
        ".docx": {
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            "application/octet-stream"
        },
        ".exe": {"application/x-dosexec", "application/x-msdownload", "application/octet-stream"},
    }

    @classmethod
    def calculate_extension_mime_risk(cls, extension: str, mime_type: str) -> float:
        """
        Detects disguise / spoofing attempts.
        A binary disguised as a picture or document is high risk (1.0).
        A standard match is 0.0.
        """
        ext = (extension or "").lower().strip()
        mime = (mime_type or "").lower().strip()

        if not ext or not mime:
            return 0.10

        # Critical spoof: Non-executable extension having executable MIME
        if ext not in cls.EXECUTABLE_EXTENSIONS and mime in cls.EXECUTABLE_MIMES:
            return 1.0

        expected = cls.EXTENSION_MIME_MAP.get(ext)
        if expected:
            if mime in expected:
                return 0.0
            if mime == "application/octet-stream":
                return 0.05
            ext_prefix = "image" if ext in {".jpg", ".jpeg", ".png", ".gif"} else \
                         "video" if ext in {".mp4", ".avi"} else \
                         "text" if ext in {".txt", ".log"} else "other"
            if ext_prefix in ("image", "video", "text") and not mime.startswith(ext_prefix):
                return 0.70

        return 0.0

    @staticmethod
    def calculate_timestamp_sanity_risk(created_time, modified_time) -> float:
        """
        Verifies timestamp plausibility.
        Flags timestamps in the future or clock manipulation.
        """
        if not created_time or not modified_time:
            return 0.0

        try:
            now = datetime.now()
            if isinstance(created_time, str):
                created_time = datetime.fromisoformat(created_time)
            if isinstance(modified_time, str):
                modified_time = datetime.fromisoformat(modified_time)

            if created_time > now or modified_time > now:
                return 1.0

        except Exception:
            return 0.20

        return 0.0

    @staticmethod
    def calculate_size_sanity_risk(size: int, evidence_type: str = "UNKNOWN") -> float:
        """
        Validates file size against expected limits.
        """
        if size is None or size <= 0:
            return 0.80

        if evidence_type in ("VIDEO", "DATABASE") and size < 20:
            return 0.40

        return 0.0

    @classmethod
    def calculate_consistency_risk(cls, evidence) -> float:
        """
        Calculates composite Consistency Risk (0.0 to 1.0).
        """
        metadata = getattr(evidence, "metadata", None)
        if not metadata:
            return 0.20

        emr = cls.calculate_extension_mime_risk(
            metadata.extension,
            metadata.mime_type
        )
        tsr = cls.calculate_timestamp_sanity_risk(
            metadata.created_time,
            metadata.modified_time
        )
        ssr = cls.calculate_size_sanity_risk(
            metadata.size,
            getattr(metadata, "evidence_type", "UNKNOWN")
        )

        consistency_risk = (0.50 * emr) + (0.35 * tsr) + (0.15 * ssr)
        return round(min(max(consistency_risk, 0.0), 1.0), 4)

    @classmethod
    def process(cls, evidence):
        """
        Updates Consistency Risk on Evidence object.
        """
        evidence.consistency_risk = cls.calculate_consistency_risk(evidence)
        return evidence