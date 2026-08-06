from ai_modules.epra.adm.rule_engine import RuleEngine
from ai_modules.epra.adm.weight_generator import WeightGenerator


class DecisionMatrix:
    """
    Builds the Adaptive Decision Matrix (ADM)
    for a given evidence type.
    """

    def __init__(self):
        self.rule_engine = RuleEngine()
        self.weight_generator = WeightGenerator()

    def build(self, evidence_type: str):
        """
        Returns the decision path and corresponding weights.
        """

        decision_path = self.rule_engine.get_decision_path(evidence_type)

        weights = self.weight_generator.generate(decision_path)

        return {
            "evidence_type": evidence_type.upper(),
            "decision_path": decision_path,
            "weights": weights
        }