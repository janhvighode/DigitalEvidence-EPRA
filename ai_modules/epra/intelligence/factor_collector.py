from ai_modules.epra.intelligence.context_analyzer import ContextAnalyzer
from ai_modules.epra.intelligence.investigation_analyzer import InvestigationAnalyzer


class FactorCollector:
    """
    Collects scores from all intelligence modules.
    """

    def __init__(self):

        self.context = ContextAnalyzer()
        self.investigation = InvestigationAnalyzer()

    def collect(self, evidence_type: str):

        factor_values = {

            # Temporary values until respective analyzers
            # are implemented.

            "semantic": 0.90,

            "authenticity": 0.80,

            "behaviour": 0.60,

            # Real analyzers

            "context":
                self.context.analyze(evidence_type),

            "investigation":
                self.investigation.analyze(evidence_type)
        }

        return factor_values