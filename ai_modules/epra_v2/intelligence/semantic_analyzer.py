"""
semantic_analyzer.py

Handles Semantic Intelligence (SI).

Currently receives semantic score from
Member 3 (CBIR / NLP Module).

Later this module can validate or preprocess
the received score if required.
"""


class SemanticAnalyzer:
    """
    Semantic Intelligence Handler.
    """

    @staticmethod
    def validate_score(score: float) -> float:
        """
        Ensures semantic score remains
        between 0 and 1.
        """

        if score < 0:
            return 0.0

        if score > 1:
            return 1.0

        return round(score, 4)

    @classmethod
    def process(cls, evidence):
        """
        Updates Semantic Intelligence.

        Currently uses dummy value.

        Later:
        evidence.semantic_score
        will come directly from
        Member 3's module.
        """

        # -----------------------------
        # Temporary Dummy Score
        # -----------------------------

        semantic_score = evidence.semantic_score

        evidence.semantic_intelligence = (
            cls.validate_score(
                semantic_score
            )
        )

        return evidence