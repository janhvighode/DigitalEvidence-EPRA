"""
Unit tests for DuplicateDetector.
"""

from ai_modules.epra_v2.intelligence.duplicate_detector import DuplicateDetector
from ai_modules.epra_v2.models.metadata import Metadata
from ai_modules.epra_v2.models.evidence import Evidence


def test_duplicate_detection():

    metadata1 = Metadata(file_name="file1.pdf",    extension=".pdf",    mime_type="application/pdf",    size=1024,    absolute_path="C:/sample/file1.pdf",    parent_directory="C:/sample",    evidence_id="1")
    metadata2 = Metadata(file_name="file2.pdf",    extension=".pdf",    mime_type="application/pdf",    size=1024,    absolute_path="C:/sample/file2.pdf",    parent_directory="C:/sample",    evidence_id="2")

    e1 = Evidence(metadata=metadata1)
    e2 = Evidence(metadata=metadata2)

    e1.generated_hash = "ABC123"
    e2.generated_hash = "ABC123"

    duplicate, original = DuplicateDetector.find_duplicate(
        e2,
        [e1]
    )

    assert duplicate is True
    assert original == "1"


def test_unique_detection():

    metadata1 = Metadata(file_name="file1.pdf",    extension=".pdf",    mime_type="application/pdf",    size=1024,    absolute_path="C:/sample/file1.pdf",    parent_directory="C:/sample",    evidence_id="1")
    metadata2 = Metadata(file_name="file2.pdf",    extension=".pdf",    mime_type="application/pdf",    size=1024,    absolute_path="C:/sample/file2.pdf",    parent_directory="C:/sample",    evidence_id="2")

    e1 = Evidence(metadata=metadata1)
    e2 = Evidence(metadata=metadata2)

    e1.generated_hash = "ABC123"
    e2.generated_hash = "XYZ456"

    duplicate, original = DuplicateDetector.find_duplicate(
        e2,
        [e1]
    )

    assert duplicate is False
    assert original is None