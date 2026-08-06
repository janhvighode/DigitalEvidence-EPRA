"""
factor_collector.py

Collects all intelligence factors required by
the Adaptive Decision Matrix (ADM).
"""


class FactorCollector:
    """
    Collects all intelligence dimensions from
    the Evidence object.
    """

    @staticmethod
    def collect(evidence):
        """
        Returns all intelligence factors required
        by the ADM.
        """

        factors = {

            "AR": evidence.authenticity_risk,

            "CI": evidence.context_intelligence,

            "BI": evidence.behaviour_intelligence,

            "SI": evidence.semantic_intelligence,

            "II": evidence.investigative_intelligence

        }

        return factors

    @classmethod
    def process(cls, evidence):

        evidence.factors = cls.collect(
            evidence
        )

        return evidence