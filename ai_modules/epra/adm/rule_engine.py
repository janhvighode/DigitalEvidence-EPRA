import json
from pathlib import Path


class RuleEngine:
    """
    Loads ADM rules and returns the decision path
    for a given evidence type.
    """

    def __init__(self):
        rules_path = Path(__file__).parent / "adm_rules.json"

        with open(rules_path, "r", encoding="utf-8") as file:
            self.rules = json.load(file)

    def get_decision_path(self, evidence_type: str):
        """
        Returns the decision path for the evidence type.
        """

        evidence_type = evidence_type.upper()

        if evidence_type in self.rules:
            return self.rules[evidence_type]["decision_path"]

        return self.rules["UNKNOWN"]["decision_path"]