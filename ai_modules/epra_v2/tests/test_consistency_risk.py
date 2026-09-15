"""
Unit tests for ConsistencyRiskAnalyzer.
"""

from datetime import datetime, timedelta
from ai_modules.epra_v2.intelligence.consistency_risk_analyzer import ConsistencyRiskAnalyzer
from ai_modules.epra_v2.models.metadata import Metadata
from ai_modules.epra_v2.models.evidence import Evidence


def test_consistent_evidence():
    now = datetime.now()
    metadata = Metadata(
        file_name="report.pdf",
        extension=".pdf",
        mime_type="application/pdf",
        size=50000,
        absolute_path="/tmp/report.pdf",
        parent_directory="/tmp",
        created_time=now - timedelta(days=5),
        modified_time=now - timedelta(days=2)
    )
    evidence = Evidence(metadata=metadata)

    risk = ConsistencyRiskAnalyzer.calculate_consistency_risk(evidence)
    assert risk == 0.0


def test_spoofed_executable_mismatch():
    now = datetime.now()
    metadata = Metadata(
        file_name="invoice.pdf",
        extension=".pdf",
        mime_type="application/x-dosexec",  # Executable disguised as PDF
        size=102400,
        absolute_path="/tmp/invoice.pdf",
        parent_directory="/tmp",
        created_time=now - timedelta(days=5),
        modified_time=now - timedelta(days=2)
    )
    evidence = Evidence(metadata=metadata)

    risk = ConsistencyRiskAnalyzer.calculate_consistency_risk(evidence)
    assert risk >= 0.50


def test_future_timestamp_anomaly():
    future_time = datetime.now() + timedelta(days=10)
    metadata = Metadata(
        file_name="photo.jpg",
        extension=".jpg",
        mime_type="image/jpeg",
        size=20000,
        absolute_path="/tmp/photo.jpg",
        parent_directory="/tmp",
        created_time=future_time,
        modified_time=future_time
    )
    evidence = Evidence(metadata=metadata)

    risk = ConsistencyRiskAnalyzer.calculate_consistency_risk(evidence)
    assert risk > 0.30


def test_consistency_risk_process_mutates_evidence():
    metadata = Metadata(
        file_name="data.txt",
        extension=".txt",
        mime_type="text/plain",
        size=150,
        absolute_path="/tmp/data.txt",
        parent_directory="/tmp"
    )
    evidence = Evidence(metadata=metadata)

    evidence = ConsistencyRiskAnalyzer.process(evidence)
    assert hasattr(evidence, "consistency_risk")
    assert 0.0 <= evidence.consistency_risk <= 1.0