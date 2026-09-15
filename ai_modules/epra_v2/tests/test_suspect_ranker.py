"""
Unit tests for SuspectRanker.
"""

from ai_modules.epra_v2.ranking.suspect_ranker import SuspectRanker
from ai_modules.epra_v2.models.suspect import Suspect
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


def test_suspect_sorting():

    s1 = Suspect("1", "Rahul")
    s2 = Suspect("2", "Amit")
    s3 = Suspect("3", "Karan")

    s1.evidence_list = [
        create_evidence("a.pdf", 80),
        create_evidence("b.pdf", 100)
    ]

    s2.evidence_list = [
        create_evidence("c.pdf", 95),
        create_evidence("d.pdf", 95),
        create_evidence("e.pdf", 70)
    ]

    s3.evidence_list = [
        create_evidence("f.pdf", 60)
    ]

    ranked = SuspectRanker.rank(
        [s1, s2, s3]
    )

    assert ranked[0].suspect_name == "Amit"
    assert ranked[1].suspect_name == "Rahul"
    assert ranked[2].suspect_name == "Karan"

    assert ranked[0].rank == 1
    assert ranked[1].rank == 2
    assert ranked[2].rank == 3