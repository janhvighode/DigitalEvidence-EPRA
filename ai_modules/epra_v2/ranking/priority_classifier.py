"""
priority_classifier.py

Classifies evidence priority
based on EPRA Score.
"""


class PriorityClassifier:
    """
    Assigns investigation priority
    from EPRA Score.
    """

    @staticmethod
    def classify(score: float) -> str:
        """
        Priority Levels

        90 - 100 : CRITICAL
        75 - 89  : HIGH
        50 - 74  : MEDIUM
        25 - 49  : LOW
        0  - 24  : VERY LOW
        """

        if score >= 90:
            return "CRITICAL"

        elif score >= 75:
            return "HIGH"

        elif score >= 50:
            return "MEDIUM"

        elif score >= 25:
            return "LOW"

        return "VERY LOW"

    @classmethod
    def process(cls, evidence):

        evidence.priority = cls.classify(
            evidence.epra_score
        )

        return evidence