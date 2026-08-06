class ContextAnalyzer:
    """
    Calculates context relevance score
    based on evidence characteristics.
    """

    CONTEXT_SCORES = {
        "IMAGE": 0.90,
        "VIDEO": 0.95,
        "AUDIO": 0.75,
        "EMAIL": 0.85,
        "PDF": 0.80,
        "DOCUMENT": 0.70,
        "DATABASE": 0.90,
        "LOG": 0.85,
        "EXECUTABLE": 0.80,
        "ARCHIVE": 0.65,
        "UNKNOWN": 0.50
    }

    def analyze(self, evidence_type: str) -> float:
        """
        Returns context relevance score.
        """

        return self.CONTEXT_SCORES.get(
            evidence_type.upper(),
            0.50
        )