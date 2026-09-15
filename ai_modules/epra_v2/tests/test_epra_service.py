"""
test_epra_service.py

Unit and integration tests for EPRAService orchestration,
covering production mode (with explicit external input tracking)
and isolated demo mode execution.
"""

from ai_modules.epra_v2.models.evidence import Evidence
from ai_modules.epra_v2.models.metadata import Metadata
from ai_modules.epra_v2.models.suspect import Suspect
from ai_modules.epra_v2.services.epra_service import EPRAService
from ai_modules.epra_v2.ranking.evidence_ranker import EvidenceRanker
from ai_modules.epra_v2.ranking.suspect_ranker import SuspectRanker
from ai_modules.epra_v2.reports.report_manager import ReportManager


def _create_sample_evidence(file_name="invoice.pdf", evidence_type="PDF"):
    metadata = Metadata(
        file_name=file_name,
        extension=".pdf" if "." not in file_name else "." + file_name.split(".")[-1],
        mime_type="application/pdf",
        size=2048,
        absolute_path="",
        evidence_type=evidence_type
    )
    return Evidence(metadata=metadata)


def test_epra_service_production_mode_tracks_missing_inputs():
    """
    In production mode (demo_mode=False), missing inputs from Member 2,
    Member 3, and Member 5 must NOT be fabricated, but tracked in pending_external_inputs.
    """
    evidence = _create_sample_evidence("crime_photo.jpg", "IMAGE")
    evidence_db = []

    processed = EPRAService.process(evidence, evidence_db, demo_mode=False)

    assert processed.processed is True
    assert "SI" in processed.pending_external_inputs
    assert "Member 3" in processed.pending_external_inputs["SI"]
    assert "BI" in processed.pending_external_inputs
    assert "Member 2" in processed.pending_external_inputs["BI"]
    assert "RELATIONSHIP" in processed.pending_external_inputs
    assert processed.semantic_intelligence == 0.0
    assert processed.behaviour_intelligence == 0.0


def test_epra_service_non_image_si_contract():
    """
    Member 3 is NOT the provider for non-image evidence.
    Non-image SI should be recorded as NOT AVAILABLE / INTEGRATION PENDING
    without attributing to Member 3.
    """
    evidence = _create_sample_evidence("transactions.xlsx", "SPREADSHEET")
    evidence_db = []

    processed = EPRAService.process(evidence, evidence_db, demo_mode=False)

    assert "SI" in processed.pending_external_inputs
    assert "Member 3" not in processed.pending_external_inputs["SI"]
    assert "Non-Image Evidence" in processed.pending_external_inputs["SI"]


def test_epra_service_consumes_supplied_external_inputs():
    """
    When Member 2 (BI factors) and Member 3 (IMAGE semantic_score) are supplied,
    EPRA must consume and calculate them correctly.
    """
    evidence = _create_sample_evidence("suspect_face.png", "IMAGE")
    evidence.semantic_score = 0.85
    evidence.access_frequency = 0.80
    evidence.repetition_factor = 0.60
    evidence.deletion_factor = 0.40
    evidence.privilege_factor = 0.60
    evidence.related_entities = ["Suspect_X"]

    evidence_db = []
    processed = EPRAService.process(evidence, evidence_db, demo_mode=False)

    assert processed.semantic_intelligence == 0.85
    assert processed.behaviour_intelligence == 0.60
    assert "SI" not in processed.pending_external_inputs
    assert "BI" not in processed.pending_external_inputs
    assert "RELATIONSHIP" not in processed.pending_external_inputs
    assert processed.epra_score > 0.0


def test_epra_service_demo_mode_execution():
    """
    In demo mode (demo_mode=True), isolated heuristics execute for standalone demonstration.
    """
    evidence = _create_sample_evidence("wallet_backup.txt", "DOCUMENT")
    evidence_db = []

    processed = EPRAService.process(evidence, evidence_db, demo_mode=True)

    assert processed.processed is True
    assert processed.semantic_intelligence > 0.0
    assert processed.behaviour_intelligence > 0.0
    assert len(processed.related_entities) > 0


def test_end_to_end_ranking_and_reporting():
    """
    Tests end-to-end pipeline: multiple evidence processing, evidence ranking,
    suspect ranking, and multi-format report generation.
    """
    ev1 = _create_sample_evidence("phishing.eml", "EMAIL")
    ev1.related_entities = ["attacker@domain.com"]
    ev1.access_frequency = 0.9
    ev1.privilege_factor = 0.7

    ev2 = _create_sample_evidence("ledger.xlsx", "SPREADSHEET")
    ev2.related_entities = ["attacker@domain.com", "insider_user"]
    ev2.access_frequency = 0.4
    ev2.privilege_factor = 0.3

    ev_db = []
    p1 = EPRAService.process(ev1, ev_db, demo_mode=True)
    ev_db.append(p1)
    p2 = EPRAService.process(ev2, ev_db, demo_mode=True)
    ev_db.append(p2)

    ranked_ev = EvidenceRanker.rank(ev_db)
    assert ranked_ev[0].rank == 1
    assert ranked_ev[1].rank == 2
    assert ranked_ev[0].epra_score >= ranked_ev[1].epra_score

    # Suspect ranking
    suspect = Suspect(suspect_id="S1", suspect_name="attacker@domain.com")
    suspect.evidence_list.extend([p1, p2])
    ranked_suspects = SuspectRanker.rank([suspect])

    assert len(ranked_suspects) == 1
    assert ranked_suspects[0].total_epra_score == round(p1.epra_score + p2.epra_score, 2)

    # Reporting
    reports = ReportManager.generate_all_reports(ranked_ev, ranked_suspects)
    assert "pdf" in reports
    assert "csv" in reports
    assert "json" in reports


def test_epra_service_with_case_context_and_suspect_detection():
    """
    Tests EPRAService with case_context and automatic possible suspect correlation.
    """
    case_ctx = {
        "description": "Cryptocurrency extortion and phishing campaign",
        "keywords": ["bitcoin", "wallet", "extortion", "ransom"]
    }

    # Evidence 1: email with suspect bitcoin address and extortion content
    m1 = Metadata(
        file_name="extortion_threat.eml",
        extension=".eml",
        mime_type="message/rfc822",
        size=400,
        absolute_path="",
        evidence_id="EV-101",
        evidence_type="EMAIL",
        extracted_text="Pay 5 bitcoin to bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq or face data leak. Contact evil@syndicate.org"
    )
    e1 = Evidence(metadata=m1)

    # Evidence 2: log file recording connection from the same attacker email/ip
    m2 = Metadata(
        file_name="c2_traffic.log",
        extension=".log",
        mime_type="text/plain",
        size=300,
        absolute_path="",
        evidence_id="EV-102",
        evidence_type="LOG",
        extracted_text="Inbound payload from evil@syndicate.org at host 198.51.100.12"
    )
    e2 = Evidence(metadata=m2)

    evidence_db = []
    p1 = EPRAService.process(e1, evidence_db, demo_mode=False, case_context=case_ctx)
    evidence_db.append(p1)
    p2 = EPRAService.process(e2, evidence_db, demo_mode=False, case_context=case_ctx)
    evidence_db.append(p2)

    # Both should have measured SI > 0 via TF-IDF against case_context
    assert p1.semantic_intelligence > 0.0
    assert "SI" not in p1.pending_external_inputs

    # Correlate and rank possible suspects
    ranked_suspects = EPRAService.correlate_and_rank_suspects(evidence_db, demo_mode=False)

    # 3 possible suspect candidates produced:
    # 1. evil@syndicate.org (linked to BOTH e1 and e2)
    # 2. bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq (in e1)
    # 3. 198.51.100.12 (in e2)
    assert len(ranked_suspects) == 3

    # Find evil@syndicate.org
    multi_evidence_suspect = next(s for s in ranked_suspects if s.suspect_name == "evil@syndicate.org")
    assert len(multi_evidence_suspect.evidence_list) == 2
    assert set(multi_evidence_suspect.linked_evidence_ids) == {"EV-101", "EV-102"}
    assert multi_evidence_suspect.total_epra_score == round(p1.epra_score + p2.epra_score, 2)

