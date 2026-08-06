from pathlib import Path

from ai_modules.epra.intelligence.factor_collector import FactorCollector
from ai_modules.epra.intelligence.metadata_extractor import MetadataExtractor
from ai_modules.epra.intelligence.evidence_classifier import EvidenceClassifier
from ai_modules.epra.adm.rule_engine import RuleEngine
from ai_modules.epra.adm.weight_generator import WeightGenerator
from ai_modules.epra.adm.decision_matrix import DecisionMatrix
from ai_modules.epra.ranking.priority_classifier import PriorityClassifier


def process_evidence(file_path: str):

    print("=" * 60)
    print(" EPRA - Evidence Processing")
    print("=" * 60)

    # Step 1
    metadata = MetadataExtractor().extract(file_path)

    # Step 2
    evidence_type = EvidenceClassifier().classify(
        metadata["file_name"]
    )

    # Step 3
    decision_path = RuleEngine().get_decision_path(
        evidence_type
    )

    # Step 4
    weights = WeightGenerator().generate(
        decision_path
    )

    # Step 5
    # Build ADM
    adm = DecisionMatrix().build(evidence_type)

    weights = adm["weights"]

# Temporary factor values (Demo)
    collector = FactorCollector()

    factor_values = collector.collect(
        evidence_type
    )

# Calculate EPRA Score
    from ai_modules.epra.ranking.epra_engine import EPRAEngine

    score = EPRAEngine().calculate_score(
        factor_values,
        weights
    )

    priority = PriorityClassifier().classify(score)

    print("\nMetadata")
    print(metadata)

    print("\nEvidence Type")
    print(evidence_type)

    print("\nDecision Path")
    print(adm["decision_path"])

    print("\nWeights")
    print(adm["weights"])
    
    print("\nEPRA Score")
    print(round(score, 3))

    print("\nPriority")
    print(priority)

    print("=" * 60)


if __name__ == "__main__":

    sample = input("Enter evidence file path: ")

    process_evidence(sample)