"""
test_chain_risk.py

Tests Chain of Custody Risk calculation.
"""

from datetime import datetime

from ai_modules.epra_v2.models.metadata import Metadata
from ai_modules.epra_v2.models.evidence import Evidence
from ai_modules.epra_v2.intelligence.chain_risk_analyzer import ChainRiskAnalyzer


def create_evidence(chain_of_custody):

    metadata = Metadata(
        file_name="sample.txt",
        extension=".txt",
        mime_type="text/plain",
        size=100,
        absolute_path="C:/sample/sample.txt",
        parent_directory="C:/sample",
        chain_of_custody=chain_of_custody
    )

    return Evidence(
        metadata=metadata
    )


def test_complete_chain_zero_risk():

    chain = [
        {
            "officer": "Investigator A",
            "role": "INVESTIGATOR",
            "action": "COLLECTED",
            "time": "2026-08-27T10:00:00"
        },
        {
            "officer": "Expert A",
            "role": "CYBER_FORENSIC_EXPERT",
            "action": "ANALYZED",
            "time": "2026-08-27T11:00:00"
        }
    ]

    evidence = create_evidence(chain)

    risk = ChainRiskAnalyzer.calculate_chain_risk(
        evidence
    )

    assert risk == 0.0


def test_missing_chain_high_risk():

    evidence = create_evidence([])

    risk = ChainRiskAnalyzer.calculate_chain_risk(
        evidence
    )

    assert risk == 1.0


def test_missing_fields_increases_risk():

    chain = [
        {
            "officer": "Investigator A",
            "role": "INVESTIGATOR",
            "time": "2026-08-27T10:00:00"
        }
    ]

    evidence = create_evidence(chain)

    risk = ChainRiskAnalyzer.calculate_chain_risk(
        evidence
    )

    assert risk > 0.0


def test_wrong_chronology_increases_risk():

    chain = [
        {
            "officer": "Investigator A",
            "role": "INVESTIGATOR",
            "action": "COLLECTED",
            "time": "2026-08-27T12:00:00"
        },
        {
            "officer": "Expert A",
            "role": "CYBER_FORENSIC_EXPERT",
            "action": "ANALYZED",
            "time": "2026-08-27T10:00:00"
        }
    ]

    evidence = create_evidence(chain)

    risk = ChainRiskAnalyzer.calculate_chain_risk(
        evidence
    )

    assert risk > 0.0


def test_unauthorized_handler_increases_risk():

    chain = [
        {
            "officer": "Unknown Person",
            "role": "UNKNOWN_ROLE",
            "action": "TRANSFERRED",
            "time": "2026-08-27T10:00:00"
        }
    ]

    evidence = create_evidence(chain)

    risk = ChainRiskAnalyzer.calculate_chain_risk(
        evidence
    )

    assert risk > 0.0