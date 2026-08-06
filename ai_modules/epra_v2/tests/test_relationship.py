"""
Unit tests for RelationshipAnalyzer.
"""

from ai_modules.epra_v2.intelligence.relationship_analyzer import RelationshipAnalyzer
from ai_modules.epra_v2.models.metadata import Metadata


def test_email_entities():

    metadata = Metadata(file_name="sample.pdf", extension=".pdf", mime_type="application/pdf",size=1024,absolute_path="C:/sample/sample.pdf",parent_directory="C:/sample")

    metadata.evidence_type = "EMAIL"

    entities = RelationshipAnalyzer.extract_entities(
        metadata
    )

    assert len(entities) == 2


def test_unknown_entities():

    metadata = Metadata(file_name="sample.pdf", extension=".pdf", mime_type="application/pdf",size=1024,absolute_path="C:/sample/sample.pdf",parent_directory="C:/sample")

    metadata.evidence_type = "UNKNOWN"

    entities = RelationshipAnalyzer.extract_entities(
        metadata
    )

    assert entities == []