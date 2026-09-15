"""
Unit tests for WeightGenerator.
"""

from ai_modules.epra_v2.adm.weight_generator import WeightGenerator
from ai_modules.epra_v2.models.metadata import Metadata
from ai_modules.epra_v2.models.evidence import Evidence


def test_weight_generation():

    metadata = Metadata(
        file_name="sample.pdf",
        extension=".pdf",
        mime_type="application/pdf",
        size=1024,
        absolute_path="C:/sample/sample.pdf",
        parent_directory="C:/sample"
    )

    # ⭐ IMPORTANT
    metadata.evidence_type = "PDF"

    evidence = Evidence(metadata=metadata)

    evidence = WeightGenerator.process(evidence)

    total = (
        evidence.authenticity_weight +
        evidence.context_weight +
        evidence.behaviour_weight +
        evidence.semantic_weight +
        evidence.investigative_weight
    )

    assert round(total, 4) == 1.0