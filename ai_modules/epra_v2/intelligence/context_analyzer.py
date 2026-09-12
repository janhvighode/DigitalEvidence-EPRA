"""
context_analyzer.py

Calculates Context Intelligence (CI)

Higher CI = Higher relevance to the investigation.
"""

from pathlib import Path


class ContextAnalyzer:

    # -------------------------------
    # High-value keywords
    # -------------------------------

    HIGH_PRIORITY_KEYWORDS = {
        "fraud",
        "transaction",
        "payment",
        "invoice",
        "bank",
        "account",
        "password",
        "otp",
        "crypto",
        "wallet",
        "evidence",
        "suspect",
        "crime",
        "attack",
        "malware",
        "ransomware",
        "phishing",
        "login",
        "credential",
        "identity",
        "money"
    }

    @classmethod
    def calculate_context_intelligence(
        cls,
        evidence_type: str,
        file_name: str
    ) -> float:
        """
        Calculates Context Intelligence.

        Returns
        -------
        float
            Normalized value between 0 and 1.
        """

        score = 0.0

        # -------------------------
        # Evidence Type Importance
        # -------------------------

        type_scores = {
            "EMAIL": 1.00,
            "PDF": 0.85,
            "DOCUMENT": 0.80,
            "DATABASE": 0.90,
            "IMAGE": 0.70,
            "VIDEO": 0.70,
            "AUDIO": 0.65,
            "LOG": 0.95,
            "EXECUTABLE": 0.90,
            "ARCHIVE": 0.60,
            "SPREADSHEET": 0.80,
            "UNKNOWN": 0.40
        }

        score += type_scores.get(evidence_type, 0.40)

        # -------------------------
        # Filename Keyword Matching
        # -------------------------

        filename = Path(file_name).stem.lower()

        for keyword in cls.HIGH_PRIORITY_KEYWORDS:

            if keyword in filename:
                score += 0.10

        # -------------------------
        # Normalize
        # -------------------------

        score = min(score, 1.0)

        return round(score, 4)

    @classmethod
    def process(cls, evidence):
        """
        Updates Context Intelligence.
        """

        evidence.context_intelligence = cls.calculate_context_intelligence(
            evidence.metadata.evidence_type,
            evidence.metadata.file_name
        )

        return evidence