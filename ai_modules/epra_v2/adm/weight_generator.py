"""
weight_generator.py

Loads ADM weights into the Evidence object.
"""

from .rule_engine import RuleEngine


class WeightGenerator:

    @classmethod
    def process(cls, evidence):

        matrix = RuleEngine.select_matrix(
            evidence.metadata.evidence_type
        )

        evidence.authenticity_weight = matrix["AR"]
        evidence.context_weight = matrix["CI"]
        evidence.behaviour_weight = matrix["BI"]
        evidence.semantic_weight = matrix["SI"]
        evidence.investigative_weight = matrix["II"]

        return evidence