"""
Unit tests for EPRAEngine.
"""

from ai_modules.epra_v2.ranking.epra_engine import EPRAEngine
from ai_modules.epra_v2.models.metadata import Metadata
from ai_modules.epra_v2.models.evidence import Evidence


def test_epra_score_range():

    metadata = Metadata(
        file_name="sample.pdf",
        extension=".pdf",
        mime_type="application/pdf",
        size=1024,
        absolute_path="C:/sample/sample.pdf",
        parent_directory="C:/sample"
)

    evidence = Evidence(metadata=metadata)

    evidence.authenticity_risk = 0.50
    evidence.context_intelligence = 0.80
    evidence.behaviour_intelligence = 0.60
    evidence.semantic_intelligence = 0.70
    evidence.investigative_intelligence = 0.90

    evidence.authenticity_weight = 0.20
    evidence.context_weight = 0.20
    evidence.behaviour_weight = 0.20
    evidence.semantic_weight = 0.20
    evidence.investigative_weight = 0.20

    evidence = EPRAEngine.process(evidence)

    assert 0.0 <= evidence.epra_score <= 100.0