"""
Unit tests for InvestigationAnalyzer.
"""

from ai_modules.epra_v2.intelligence.investigation_analyzer import InvestigationAnalyzer
from ai_modules.epra_v2.models.metadata import Metadata
from ai_modules.epra_v2.models.evidence import Evidence


def test_investigation_score_range():

    metadata = Metadata(file_name="sample.pdf", extension=".pdf", mime_type="application/pdf",size=1024,absolute_path="C:/sample/sample.pdf",parent_directory="C:/sample")

    metadata.evidence_type = "EMAIL"

    metadata.file_name = "location_mail.pdf"

    metadata.created_time = "2025"

    evidence = Evidence(metadata=metadata)

    evidence.related_entities = ["Amit"]

    score = InvestigationAnalyzer.calculate_investigation_intelligence(
        evidence
    )

    assert 0.0 <= score <= 1.0


def test_suspect_factor():

    metadata = Metadata(file_name="sample.pdf", extension=".pdf", mime_type="application/pdf",size=1024,absolute_path="C:/sample/sample.pdf",parent_directory="C:/sample")

    evidence = Evidence(metadata=metadata)

    evidence.related_entities = ["Rahul"]

    assert InvestigationAnalyzer.suspect_factor(
        evidence
    ) == 1.0


def test_no_suspect_factor():

    metadata = Metadata(file_name="sample.pdf", extension=".pdf", mime_type="application/pdf",size=1024,absolute_path="C:/sample/sample.pdf",parent_directory="C:/sample")

    evidence = Evidence(metadata=metadata)

    evidence.related_entities = []

    assert InvestigationAnalyzer.suspect_factor(
        evidence
    ) == 0.0