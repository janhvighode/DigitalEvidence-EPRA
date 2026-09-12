"""
Unit tests for FactorCollector.
"""

from ai_modules.epra_v2.intelligence.factor_collector import FactorCollector
from ai_modules.epra_v2.models.metadata import Metadata
from ai_modules.epra_v2.models.evidence import Evidence


def test_factor_collection():

    metadata = Metadata(file_name="sample.pdf", extension=".pdf",mime_type="application/pdf", size=1024, absolute_path="C:/sample/sample.pdf", parent_directory="C:/sample")

    evidence = Evidence(metadata=metadata)

    evidence.authenticity_risk = 0.4
    evidence.context_intelligence = 0.6
    evidence.behaviour_intelligence = 0.5
    evidence.semantic_intelligence = 0.8
    evidence.investigative_intelligence = 0.9

    factors = FactorCollector.collect(evidence)

    assert factors["AR"] == 0.4
    assert factors["CI"] == 0.6
    assert factors["BI"] == 0.5
    assert factors["SI"] == 0.8
    assert factors["II"] == 0.9