"""
rule_engine.py

Selects the correct ADM based on
evidence type.
"""

from .decision_matrix import ADM_TABLE


class RuleEngine:

    @staticmethod
    def select_matrix(evidence_type: str):

        return ADM_TABLE.get(
            evidence_type.upper(),
            ADM_TABLE["UNKNOWN"]
        )