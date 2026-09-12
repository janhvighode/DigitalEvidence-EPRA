"""
Unit tests for IntegrityRiskAnalyzer.
"""

from datetime import datetime, timedelta
from ai_modules.epra_v2.intelligence.integrity_risk_analyzer import IntegrityRiskAnalyzer
from ai_modules.epra_v2.models.metadata import Metadata
from ai_modules.epra_v2.models.evidence import Evidence


def test_clean_evidence_integrity_risk():
    metadata = Metadata(
        file_name="disk_image.raw",
        extension=".raw",
        mime_type="application/octet-stream",
        size=1048576,
        absolute_path="/tmp/disk_image.raw",
        parent_directory="/tmp",
        acquisition_method="Disk Imaging",
        collection_time=datetime.now() - timedelta(days=2),
        modified_time=datetime.now() - timedelta(days=5)
    )
    evidence = Evidence(metadata=metadata)
    evidence.corruption_detected = False

    risk = IntegrityRiskAnalyzer.calculate_integrity_risk(evidence)
    assert risk == 0.0


def test_corruption_detected_raises_risk():
    metadata = Metadata(
        file_name="corrupt.dat",
        extension=".dat",
        mime_type="application/octet-stream",
        size=512,
        absolute_path="/tmp/corrupt.dat",
        parent_directory="/tmp"
    )
    evidence = Evidence(metadata=metadata)
    evidence.corruption_detected = True

    risk = IntegrityRiskAnalyzer.calculate_integrity_risk(evidence)
    assert risk == 1.0


def test_post_acquisition_tamper_detected():
    now = datetime.now()
    metadata = Metadata(
        file_name="evidence.pdf",
        extension=".pdf",
        mime_type="application/pdf",
        size=2048,
        absolute_path="/tmp/evidence.pdf",
        parent_directory="/tmp",
        acquisition_method="Logical Acquisition",
        collection_time=now - timedelta(days=2),
        modified_time=now - timedelta(days=1)  # modified AFTER collection!
    )
    evidence = Evidence(metadata=metadata)

    risk = IntegrityRiskAnalyzer.calculate_integrity_risk(evidence)
    assert risk == 1.0


def test_integrity_risk_process_mutates_evidence():
    metadata = Metadata(
        file_name="sample.txt",
        extension=".txt",
        mime_type="text/plain",
        size=100,
        absolute_path="/tmp/sample.txt",
        parent_directory="/tmp",
        acquisition_method="Write-Blocked Copy"
    )
    evidence = Evidence(metadata=metadata)

    evidence = IntegrityRiskAnalyzer.process(evidence)
    assert hasattr(evidence, "integrity_risk")
    assert 0.0 <= evidence.integrity_risk <= 1.0