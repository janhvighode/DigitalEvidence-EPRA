class PriorityClassifier:
    """
    Classifies evidence priority based on EPRA score.
    """

    def classify(self, score: float) -> str:

        if score >= 0.90:
            return "CRITICAL"

        elif score >= 0.75:
            return "HIGH"

        elif score >= 0.50:
            return "MEDIUM"

        return "LOW"