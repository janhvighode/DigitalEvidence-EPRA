"""
investigation_analyzer.py

Calculates Investigation Intelligence (II)

Formula:
II = (SF + CF + FF + LF + TF) / 5
"""

from pathlib import Path


class InvestigationAnalyzer:
    """
    Calculates Investigation Intelligence.
    """

    # -----------------------------------------
    # Communication Evidence
    # -----------------------------------------

    COMMUNICATION_TYPES = {
        "EMAIL",
        "CHAT",
        "SMS",
        "CALL_LOG"
    }

    # -----------------------------------------
    # Financial Evidence
    # -----------------------------------------

    FINANCIAL_TYPES = {
        "BANK",
        "BANK_STATEMENT",
        "TRANSACTION",
        "UPI",
        "CRYPTO"
    }

    # -----------------------------------------
    # Location Keywords
    # -----------------------------------------

    LOCATION_KEYWORDS = {
        "gps",
        "latitude",
        "longitude",
        "location",
        "address",
        "exif"
    }

    @staticmethod
    def suspect_factor(evidence):

        return 1.0 if len(evidence.related_entities) > 0 else 0.0

    @classmethod
    def communication_factor(cls, evidence):

        if evidence.metadata.evidence_type in cls.COMMUNICATION_TYPES:
            return 1.0

        return 0.0

    @classmethod
    def financial_factor(cls, evidence):

        if evidence.metadata.evidence_type in cls.FINANCIAL_TYPES:
            return 1.0

        return 0.0

    @classmethod
    def location_factor(cls, evidence):

        filename = evidence.metadata.file_name.lower()

        for keyword in cls.LOCATION_KEYWORDS:

            if keyword in filename:
                return 1.0

        return 0.0

    @staticmethod
    def timeline_factor(evidence):

        if evidence.metadata.created_time:
            return 1.0

        return 0.0

    @classmethod
    def calculate_investigation_intelligence(
        cls,
        evidence
    ):

        sf = cls.suspect_factor(evidence)

        cf = cls.communication_factor(evidence)

        ff = cls.financial_factor(evidence)

        lf = cls.location_factor(evidence)

        tf = cls.timeline_factor(evidence)

        score = (
            sf +
            cf +
            ff +
            lf +
            tf
        ) / 5

        return round(score, 4)

    @classmethod
    def process(cls, evidence):

        evidence.investigative_intelligence = (
            cls.calculate_investigation_intelligence(
                evidence
            )
        )

        return evidence