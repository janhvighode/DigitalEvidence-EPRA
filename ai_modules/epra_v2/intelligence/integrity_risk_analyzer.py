"""
integrity_risk_analyzer.py

Calculates Integrity Risk (IR) from forensic acquisition and integrity facts.

Formula:
Integrity Risk represents the probability that the evidence has been
corrupted, improperly acquired, or altered post-acquisition.
"""

from datetime import datetime
from typing import Optional


class IntegrityRiskAnalyzer:
    """
    Evaluates forensic acquisition and validation integrity.
    """

    RECOGNIZED_ACQUISITION_METHODS = {
        "DISK IMAGING",
        "PHYSICAL ACQUISITION",
        "LOGICAL ACQUISITION",
        "LIVE ACQUISITION",
        "MEMORY DUMP",
        "TARGETED COPY",
        "WRITE-BLOCKED COPY"
    }

    @classmethod
    def calculate_acquisition_risk(cls, metadata) -> float:
        """
        Evaluates method used during evidence acquisition.
        Forensic write-blocked imaging is standard (0.0 risk).
        Missing or unknown acquisition method raises risk.
        """
        method = getattr(metadata, "acquisition_method", None)
        if not method:
            return 0.30

        if str(method).strip().upper() in cls.RECOGNIZED_ACQUISITION_METHODS:
            return 0.0

        return 0.20

    @staticmethod
    def calculate_corruption_risk(evidence) -> float:
        """
        Checks for detected file corruption or invalid validation status.
        """
        if getattr(evidence, "corruption_detected", False):
            return 1.0

        if getattr(evidence, "tampered", False):
            return 1.0

        validation_status = getattr(evidence, "validation_status", None)
        if not validation_status and hasattr(evidence, "metadata"):
            validation_status = getattr(evidence.metadata, "validation_status", None)

        if validation_status:
            status = str(validation_status).strip().upper()
            if status in ("CORRUPT", "CORRUPTED", "TAMPERED", "INVALID"):
                return 1.0
            if status == "EMPTY":
                return 0.80
            if status in ("VALID", "VERIFIED"):
                return 0.0

        return 0.0

    @staticmethod
    def calculate_post_acquisition_modification_risk(metadata) -> float:
        """
        Checks if file modification time is after forensic collection time.
        Any modification post-collection severely undermines integrity.
        """
        collection_time = getattr(metadata, "collection_time", None)
        modified_time = getattr(metadata, "modified_time", None)

        if not collection_time or not modified_time:
            return 0.0

        try:
            if isinstance(collection_time, str):
                collection_time = datetime.fromisoformat(collection_time)
            if isinstance(modified_time, str):
                modified_time = datetime.fromisoformat(modified_time)

            if modified_time > collection_time:
                return 1.0
        except Exception:
            return 0.20

        return 0.0

    @classmethod
    def calculate_integrity_risk(cls, evidence) -> float:
        """
        Calculates normalized Integrity Risk (0.0 to 1.0).
        """
        metadata = getattr(evidence, "metadata", None)

        corruption_risk = cls.calculate_corruption_risk(evidence)
        if corruption_risk >= 1.0:
            return 1.0

        post_mod_risk = (
            cls.calculate_post_acquisition_modification_risk(metadata)
            if metadata else 0.0
        )
        if post_mod_risk >= 1.0:
            return 1.0

        acquisition_risk = (
            cls.calculate_acquisition_risk(metadata)
            if metadata else 0.30
        )

        integrity_risk = (
            0.50 * corruption_risk
            + 0.30 * post_mod_risk
            + 0.20 * acquisition_risk
        )

        return round(min(max(integrity_risk, 0.0), 1.0), 4)

    @classmethod
    def process(cls, evidence):
        """
        Updates Integrity Risk on Evidence object.
        """
        evidence.integrity_risk = cls.calculate_integrity_risk(evidence)
        return evidence