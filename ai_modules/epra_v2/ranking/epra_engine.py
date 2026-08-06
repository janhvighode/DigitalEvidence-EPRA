"""
epra_engine.py

Core mathematical engine of EPRA V2.

Calculates

1. Investigation Priority Index (IPI)
2. EPRA Score
"""

class EPRAEngine:

    """
    Core EPRA Mathematical Engine.
    """

    @staticmethod
    def calculate_ipi(evidence):
        """
        IPI =
        (AR × WAR) +
        (CI × WCI) +
        (BI × WBI) +
        (SI × WSI) +
        (II × WII)
        """

        ipi = (

            evidence.authenticity_risk
            * evidence.authenticity_weight

            +

            evidence.context_intelligence
            * evidence.context_weight

            +

            evidence.behaviour_intelligence
            * evidence.behaviour_weight

            +

            evidence.semantic_intelligence
            * evidence.semantic_weight

            +

            evidence.investigative_intelligence
            * evidence.investigative_weight

        )

        return round(ipi, 4)

    @staticmethod
    def calculate_epra_score(ipi):
        """
        Converts IPI into percentage.
        """

        return round(
            ipi * 100,
            2
        )

    @classmethod
    def process(cls, evidence):

        ipi = cls.calculate_ipi(
            evidence
        )

        evidence.investigation_priority_index = ipi

        evidence.epra_score = (
            cls.calculate_epra_score(
                ipi
            )
        )

        return evidence