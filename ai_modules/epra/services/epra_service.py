from ai_modules.epra.intelligence.metadata_extractor import MetadataExtractor
from ai_modules.epra.intelligence.evidence_classifier import EvidenceClassifier
from ai_modules.epra.intelligence.factor_collector import FactorCollector

from ai_modules.epra.adm.decision_matrix import DecisionMatrix

from ai_modules.epra.ranking.epra_engine import EPRAEngine
from ai_modules.epra.ranking.priority_classifier import PriorityClassifier


class EPRAService:
    """
    Complete EPRA processing pipeline.
    This class will be called by the backend.
    """

    def __init__(self):

        self.metadata = MetadataExtractor()
        self.classifier = EvidenceClassifier()
        self.matrix = DecisionMatrix()
        self.collector = FactorCollector()
        self.engine = EPRAEngine()
        self.priority = PriorityClassifier()

    def process(self, file_path: str):

        metadata = self.metadata.extract(file_path)

        evidence_type = self.classifier.classify(
            metadata["file_name"]
        )

        adm = self.matrix.build(evidence_type)

        factor_values = self.collector.collect(
            evidence_type
        )

        score = self.engine.calculate_score(
            factor_values,
            adm["weights"]
        )

        priority = self.priority.classify(score)

        return {

            "metadata": metadata,

            "evidence_type": evidence_type,

            "decision_path": adm["decision_path"],

            "weights": adm["weights"],

            "factor_values": factor_values,

            "epra_score": score,

            "priority": priority
        }