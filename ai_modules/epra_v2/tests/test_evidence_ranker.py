"""
Unit tests for EvidenceRanker.
"""

from ai_modules.epra_v2.ranking.evidence_ranker import EvidenceRanker
from ai_modules.epra_v2.models.metadata import Metadata
from ai_modules.epra_v2.models.evidence import Evidence


def create_metadata(file_name):

    return Metadata(
        file_name=file_name,
        extension=".pdf",
        mime_type="application/pdf",
        size=1024,
        absolute_path=f"C:/sample/{file_name}",
        parent_directory="C:/sample"
    )


def create_evidence(file_name, score):

    metadata = create_metadata(file_name)

    evidence = Evidence(metadata=metadata)
    evidence.epra_score = score

    return evidence


def test_evidence_sorting():

    e1 = create_evidence("B.pdf", 80)
    e2 = create_evidence("A.pdf", 80)
    e3 = create_evidence("C.pdf", 95)

    ranked = EvidenceRanker.rank([e1, e2, e3])

    assert ranked[0].epra_score == 95
    assert ranked[1].metadata.file_name == "A.pdf"
    assert ranked[2].metadata.file_name == "B.pdf"