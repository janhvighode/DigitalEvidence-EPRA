class InvestigationAnalyzer:
    """
    Estimates how important a type of evidence is
    during an investigation.
    """

    INVESTIGATION_SCORES = {
        "IMAGE": 0.95,
        "VIDEO": 1.00,
        "AUDIO": 0.70,
        "EMAIL": 0.90,
        "PDF": 0.80,
        "DOCUMENT": 0.75,
        "DATABASE": 0.95,
        "LOG": 0.90,
        "EXECUTABLE": 0.95,
        "ARCHIVE": 0.65,
        "UNKNOWN": 0.50
    }

    def analyze(self, evidence_type: str) -> float:
        """
        Returns investigation importance score.
        """

        return self.INVESTIGATION_SCORES.get(
            evidence_type.upper(),
            0.50
        )