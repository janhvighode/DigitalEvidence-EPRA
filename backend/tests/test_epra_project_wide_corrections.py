"""
EPRA Project-Wide Integration Corrections - Master Test Suite.
Verifies all 10 core integration requirements (TEST A through TEST J):
- TEST A: Exact priority threshold boundaries (0.0, 24.99, 25.0, 49.99, 50.0, 74.99, 75.0, 89.99, 90.0, 100.0)
- TEST B: Scale separation (IPI in [0.0, 1.0] vs EPRA score in [0.0, 100.0])
- TEST C: Canonical evidence type normalizer (12 types, raw MIME handling, extensions, fallbacks)
- TEST D: IMAGE semantic intelligence (genuine CBIR score vs missing/pending NULL)
- TEST E: Non-image semantic intelligence (genuine text content vs missing/pending NULL)
- TEST F: Behavioural intelligence (actual measured 0.0 vs missing NULL)
- TEST G: Dynamic case EPRA summary and aggregations
- TEST H: Evidence ranker (genuine rank derivation from EvidenceRanker)
- TEST I: Cross-consumer consistency (Cyber Expert, Investigator, Report, PDF, Suspect Ranking, Admin Stats)
- TEST J: Authorization and cross-case data isolation
"""
import sys
from pathlib import Path
from datetime import datetime, timezone
import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from fastapi import HTTPException

# Ensure project root and backend are on sys.path
root_dir = Path(__file__).resolve().parent.parent.parent
if str(root_dir) not in sys.path:
    sys.path.insert(0, str(root_dir))
backend_dir = Path(__file__).resolve().parent.parent
if str(backend_dir) not in sys.path:
    sys.path.insert(0, str(backend_dir))

from database.database import Base
from models.user import User
from models.role import Role
from models.city import City
from models.cyber_cell import CyberCell
from models.case import Case
from models.evidence import Evidence
from models.evidence_hash import EvidenceHash
from models.epra_result import EPRAResult
from models.cbir_result import CBIRResult
from models.report_record import ReportRecord
from models.notification import Notification
from models.possible_entity import PossibleEntity, PossibleEntityEvidenceLink
from models.evidence_link import EvidenceLink
from models.evidence_record import EvidenceRecord
from models.case_timeline import CaseTimeline
from models.custody_log import CustodyLog
from models.activity_log import ActivityLog

from ai_modules.epra_v2.ranking.priority_classifier import PriorityClassifier
from ai_modules.epra_v2.ranking.evidence_ranker import EvidenceRanker
from ai_modules.epra_v2.models.evidence import Evidence as JanhviEvidence
from ai_modules.epra_v2.models.metadata import Metadata as JanhviMetadata
from ai_modules.epra_v2.services.epra_service import EPRAService as JanhviEPRAService

from services.epra_service import (
    CANONICAL_EPRA_TYPES,
    normalize_epra_evidence_type,
    process_case_epra,
    get_case_epra_summary,
    get_case_ranked_evidence,
    get_evidence_epra_detail,
    calculate_summary_metrics,
    authorize_cyber_expert_case_access,
    authorize_epra_read_case_access
)
from services.technical_report_service import TechnicalReportService
from services.suspect_ranking_service import get_possible_entity_detail
from services.admin_system_statistics_service import AdminSystemStatisticsService
from services.investigator_dashboard_service import (
    get_investigator_analysis_evidence_repository,
    get_investigator_single_analysis_detail,
    get_investigator_epra_priority_distribution
)
from services.investigator_analysis_updates_service import InvestigatorAnalysisUpdatesService
from services.pdf_service import PDFService


def make_user(id: int, full_name: str, role_id: int, cyber_cell_id: int = 1, username: str = None) -> User:
    uname = username or f"user_{id}"
    return User(
        id=id,
        full_name=full_name,
        username=uname,
        email=f"{uname}@test.gov",
        phone_number="1234567890",
        password="hashed_password",
        role_id=role_id,
        cyber_cell_id=cyber_cell_id,
        is_first_login=False,
        is_active=True
    )


@pytest.fixture
def db_session():
    """Create a fully isolated in-memory SQLite database for testing."""
    engine = create_engine("sqlite:///:memory:", echo=False)
    Base.metadata.create_all(
        engine,
        tables=[
            Role.__table__,
            City.__table__,
            CyberCell.__table__,
            User.__table__,
            Case.__table__,
            Evidence.__table__,
            EvidenceHash.__table__,
            EPRAResult.__table__,
            CBIRResult.__table__,
            ReportRecord.__table__,
            Notification.__table__,
            PossibleEntity.__table__,
            PossibleEntityEvidenceLink.__table__,
            EvidenceLink.__table__,
            EvidenceRecord.__table__,
            CaseTimeline.__table__,
            CustodyLog.__table__,
            ActivityLog.__table__
        ]
    )
    Session = sessionmaker(bind=engine)
    db = Session()

    # Pre-seed default City and CyberCell
    city = City(id=1, city_name="Default City")
    cell = CyberCell(id=1, cyber_cell_name="Default Cell", admin_email="admin@default.gov", city_id=1)
    db.add_all([city, cell])
    db.commit()

    try:
        yield db
    finally:
        db.close()


# ==============================================================================
# TEST A: EXACT THRESHOLD VERIFICATION
# ==============================================================================

def test_a_exact_priority_threshold_boundaries():
    """
    Verify Janhvi's PriorityClassifier exact thresholds:
    - 0.0 -> VERY LOW
    - 24.99 -> VERY LOW
    - 25.0 -> LOW
    - 49.99 -> LOW
    - 50.0 -> MEDIUM
    - 74.99 -> MEDIUM
    - 75.0 -> HIGH
    - 89.99 -> HIGH
    - 90.0 -> CRITICAL
    - 100.0 -> CRITICAL
    Verify canonical display has space ('VERY LOW') rather than underscore.
    """
    test_cases = [
        (0.0, "VERY LOW"),
        (10.5, "VERY LOW"),
        (24.99, "VERY LOW"),
        (25.0, "LOW"),
        (35.0, "LOW"),
        (49.99, "LOW"),
        (50.0, "MEDIUM"),
        (65.5, "MEDIUM"),
        (74.99, "MEDIUM"),
        (75.0, "HIGH"),
        (82.0, "HIGH"),
        (89.99, "HIGH"),
        (90.0, "CRITICAL"),
        (95.5, "CRITICAL"),
        (100.0, "CRITICAL"),
    ]
    for score, expected_priority in test_cases:
        p = PriorityClassifier.classify(score)
        assert p == expected_priority, f"Score {score} should classify as {expected_priority}, got {p}"
        assert "_" not in p, f"Priority string '{p}' must use spaces, not underscores"


# ==============================================================================
# TEST B: SCALE SEPARATION
# ==============================================================================

def test_b_scale_separation(db_session):
    """
    Verify strict separation between IPI [0.0, 1.0] and EPRA Score [0.0, 100.0]:
    - IPI is never on 0-100 scale
    - EPRA score is never on 0-1 scale
    - Neither is converted to the other's scale
    """
    # Create test case and evidence
    expert = make_user(id=301, full_name="Cyber Expert 1", role_id=3)
    db_session.add(expert)
    case = Case(id=101, case_id="CASE-SCALE-001", title="Scale Test Case", cyber_expert_id=301, status="Open")
    db_session.add(case)
    ev = Evidence(
        id=201,
        case_id=101,
        evidence_id="EV-SCALE-001",
        file_name="sample.pdf",
        file_type="PDF",
        file_size=1024,
        file_path="uploads/evidence/101/sample.pdf"
    )
    db_session.add(ev)
    db_session.commit()

    # Process EPRA
    res = process_case_epra(db_session, case_id=101, current_user=expert, demo_mode=True)
    assert res["status"] == "SUCCESS"
    assert len(res["results"]) == 1
    r = res["results"][0]

    # Verify IPI scale [0.0, 1.0]
    assert r["ipi"] is not None
    assert 0.0 <= r["ipi"] <= 1.0, f"IPI {r['ipi']} must be in [0.0, 1.0]"

    # Verify EPRA Score scale [0.0, 100.0]
    assert r["epra_score"] is not None
    assert 0.0 <= r["epra_score"] <= 100.0, f"EPRA Score {r['epra_score']} must be in [0.0, 100.0]"

    # Check database persistence
    db_record = db_session.query(EPRAResult).filter(EPRAResult.evidence_id == 201).first()
    assert db_record is not None
    assert 0.0 <= db_record.ipi <= 1.0
    assert 0.0 <= db_record.epra_score <= 100.0


# ==============================================================================
# TEST C: CANONICAL EVIDENCE TYPE NORMALIZER
# ==============================================================================

def test_c_canonical_evidence_type_normalizer():
    """
    Verify canonical evidence type normalizer across all 12 types, raw MIME types,
    extensions, case insensitivity, and fallbacks.
    """
    expected_12_types = {
        "IMAGE", "VIDEO", "AUDIO", "EMAIL", "PDF", "DOCUMENT",
        "SPREADSHEET", "EXECUTABLE", "DATABASE", "LOG", "ARCHIVE", "UNKNOWN"
    }
    assert CANONICAL_EPRA_TYPES == expected_12_types

    # 1. Exact string matches across cases
    assert normalize_epra_evidence_type("image") == "IMAGE"
    assert normalize_epra_evidence_type("IMAGE") == "IMAGE"
    assert normalize_epra_evidence_type("video") == "VIDEO"
    assert normalize_epra_evidence_type("Audio") == "AUDIO"
    assert normalize_epra_evidence_type("Email") == "EMAIL"
    assert normalize_epra_evidence_type("PDF") == "PDF"
    assert normalize_epra_evidence_type("Document") == "DOCUMENT"
    assert normalize_epra_evidence_type("SPREADSHEET") == "SPREADSHEET"
    assert normalize_epra_evidence_type("Executable") == "EXECUTABLE"
    assert normalize_epra_evidence_type("Database") == "DATABASE"
    assert normalize_epra_evidence_type("Log") == "LOG"
    assert normalize_epra_evidence_type("Archive") == "ARCHIVE"

    # 2. Raw MIME types
    assert normalize_epra_evidence_type("image/jpeg") == "IMAGE"
    assert normalize_epra_evidence_type("image/png") == "IMAGE"
    assert normalize_epra_evidence_type("video/mp4") == "VIDEO"
    assert normalize_epra_evidence_type("audio/mpeg") == "AUDIO"
    assert normalize_epra_evidence_type("message/rfc822") == "EMAIL"
    assert normalize_epra_evidence_type("application/pdf") == "PDF"
    assert normalize_epra_evidence_type("application/msword") == "DOCUMENT"
    assert normalize_epra_evidence_type("text/csv") == "SPREADSHEET"
    assert normalize_epra_evidence_type("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet") == "SPREADSHEET"
    assert normalize_epra_evidence_type("application/x-msdownload") == "EXECUTABLE"
    assert normalize_epra_evidence_type("application/zip") == "ARCHIVE"
    assert normalize_epra_evidence_type("text/plain") == "DOCUMENT"

    # 3. Filename extensions
    assert normalize_epra_evidence_type(filename="suspicious.exe") == "EXECUTABLE"
    assert normalize_epra_evidence_type(filename="network.pcap") == "LOG"
    assert normalize_epra_evidence_type(filename="records.sqlite") == "DATABASE"
    assert normalize_epra_evidence_type(filename="financials.xlsx") == "SPREADSHEET"
    assert normalize_epra_evidence_type(filename="contract.docx") == "DOCUMENT"
    assert normalize_epra_evidence_type(filename="backup.tar.gz") == "ARCHIVE"
    assert normalize_epra_evidence_type(filename="conversation.eml") == "EMAIL"

    # 4. Edge cases & fallback
    assert normalize_epra_evidence_type(None, None) == "UNKNOWN"
    assert normalize_epra_evidence_type("", "") == "UNKNOWN"
    assert normalize_epra_evidence_type("invalid/nonsense/mime") == "UNKNOWN"


# ==============================================================================
# TEST D: IMAGE SEMANTIC INTELLIGENCE: GENUINE CBIR VS MISSING
# ==============================================================================

def test_d_image_semantic_intelligence_genuine_cbir_vs_missing(db_session):
    """
    Verify Critical SI Rule:
    1. IMAGE with genuine CBIR semantic score in DB:
       - semantic_intelligence == score
       - semantic_status == 'MEASURED'
       - analysis_status == 'COMPLETE'
       - pending_external_inputs does NOT include CBIR warning
    2. IMAGE without CBIR score:
       - semantic_intelligence is None (NULL in DB)
       - semantic_status == 'PENDING'
       - analysis_status == 'PARTIAL / PENDING INPUTS'
       - pending_external_inputs includes 'Awaiting IMAGE CBIR/Semantic score'
       - Score is computed without hallucinating SI = 0.0
    """
    expert = make_user(id=302, full_name="Cyber Expert 2", role_id=3)
    db_session.add(expert)
    case = Case(id=102, case_id="CASE-SI-002", title="SI Test Case", cyber_expert_id=302, status="Open")
    db_session.add(case)

    # Ev 1: Image WITH persisted CBIR result
    ev1 = Evidence(
        id=202,
        case_id=102,
        evidence_id="EV-IMG-CBIR",
        file_name="suspect_photo.jpg",
        file_type="IMAGE",
        file_size=2048,
        file_path="uploads/evidence/102/suspect_photo.jpg"
    )
    db_session.add(ev1)
    cbir = CBIRResult(
        case_id=102,
        query_evidence_id=202,
        candidate_evidence_id=202,
        semantic_score=0.85,
        visual_similarity_score=0.91,
        classification="Very Strong Visual Match",
        confidence_level="High",
        recommendation="Review visually",
        reason="High visual match",
        sha256_exact_duplicate=False
    )
    db_session.add(cbir)

    # Ev 2: Image WITHOUT CBIR result
    ev2 = Evidence(
        id=203,
        case_id=102,
        evidence_id="EV-IMG-NOCBIR",
        file_name="scene_overview.png",
        file_type="IMAGE",
        file_size=4096,
        file_path="uploads/evidence/102/scene_overview.png"
    )
    db_session.add(ev2)
    db_session.commit()

    # Process with demo_mode=True and provide behaviour_intelligence so only SI differs
    res = process_case_epra(
        db_session,
        case_id=102,
        current_user=expert,
        demo_mode=True,
        external_inputs={"behavioural_intelligence": 0.5}
    )
    assert res["status"] == "SUCCESS"

    r1 = next(r for r in res["results"] if r["evidence_id"] == "EV-IMG-CBIR")
    r2 = next(r for r in res["results"] if r["evidence_id"] == "EV-IMG-NOCBIR")

    # EV 1: Has genuine CBIR score
    assert r1["semantic_intelligence"] == 0.85
    assert r1["semantic_status"] == "MEASURED"
    assert r1["analysis_status"] == "COMPLETE"
    assert not any("CBIR" in p for p in r1["pending_external_inputs"])

    # EV 2: Missing CBIR score
    assert r2["semantic_intelligence"] is None
    assert r2["semantic_status"] == "PENDING"
    assert r2["analysis_status"] == "PARTIAL / PENDING INPUTS"
    assert any("Awaiting IMAGE CBIR/Semantic score" in p for p in r2["pending_external_inputs"])


# ==============================================================================
# TEST E: NON-IMAGE SEMANTIC INTELLIGENCE: GENUINE CONTENT VS MISSING
# ==============================================================================

def test_e_non_image_semantic_intelligence(db_session):
    """
    Verify Non-Image Semantic Intelligence handling:
    1. With extracted content and context: genuine semantic calculation, MEASURED status.
    2. Without extracted text and without context: semantic_intelligence is None (NULL),
       PENDING status, PARTIAL / PENDING INPUTS, not defaulted to 0.0.
    """
    expert = make_user(id=303, full_name="Cyber Expert 3", role_id=3)
    db_session.add(expert)
    case = Case(id=103, case_id="CASE-NONIMG-003", title="Phishing Investigation", cyber_expert_id=303, status="Open")
    db_session.add(case)

    # Document 1: Provided with extracted content and context
    ev1 = Evidence(
        id=204,
        case_id=103,
        evidence_id="EV-DOC-WITHCONTENT",
        file_name="ransom_note.txt",
        file_type="DOCUMENT",
        file_size=512,
        file_path="uploads/evidence/103/ransom_note.txt"
    )
    db_session.add(ev1)

    # Document 2: Empty, no content, no context
    ev2 = Evidence(
        id=205,
        case_id=103,
        evidence_id="EV-DOC-NOCONTENT",
        file_name="blank.txt",
        file_type="DOCUMENT",
        file_size=0,
        file_path="uploads/evidence/103/blank.txt"
    )
    db_session.add(ev2)
    db_session.commit()

    external_inputs = {
        "EV-DOC-WITHCONTENT": {
            "content": "Please send 5 bitcoin to wallet 1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa or files will be destroyed.",
            "context": "Cyber extortion ransom demands cryptocurrency payment.",
            "behavioural_intelligence": 0.4
        },
        "EV-DOC-NOCONTENT": {
            "behavioural_intelligence": 0.4
            # Content and context omitted
        }
    }

    res = process_case_epra(db_session, case_id=103, current_user=expert, demo_mode=True, external_inputs=external_inputs)
    assert res["status"] == "SUCCESS"

    r1 = next(r for r in res["results"] if r["evidence_id"] == "EV-DOC-WITHCONTENT")
    r2 = next(r for r in res["results"] if r["evidence_id"] == "EV-DOC-NOCONTENT")

    # Document 1: Has genuine content and context
    assert r1["semantic_status"] == "MEASURED"
    assert r1["semantic_intelligence"] is not None
    assert 0.0 <= r1["semantic_intelligence"] <= 1.0

    # Document 2: Lacks content & context -> None (NULL), not defaulted to 0.0
    assert r2["semantic_intelligence"] is None
    assert r2["semantic_status"] == "PENDING"
    assert r2["analysis_status"] == "PARTIAL / PENDING INPUTS"
    assert any("text content" in p.lower() or "context" in p.lower() for p in r2["pending_external_inputs"])


# ==============================================================================
# TEST F: BEHAVIOURAL INTELLIGENCE: ACTUAL ZERO VS MISSING
# ==============================================================================

def test_f_behavioural_intelligence_actual_zero_vs_missing(db_session):
    """
    Verify Behavioural Intelligence:
    1. Actual measured 0.0: stored as 0.0, NOT treated as missing, not in pending inputs.
    2. Missing input: stored as None (NULL in DB), noted in pending inputs.
    """
    expert = make_user(id=304, full_name="Cyber Expert 4", role_id=3)
    db_session.add(expert)
    case = Case(id=104, case_id="CASE-BI-004", title="BI Test Case", cyber_expert_id=304, status="Open")
    db_session.add(case)

    ev1 = Evidence(
        id=206,
        case_id=104,
        evidence_id="EV-BI-ZERO",
        file_name="normal_log.log",
        file_type="LOG",
        file_size=1024,
        file_path="uploads/evidence/104/normal_log.log"
    )
    ev2 = Evidence(
        id=207,
        case_id=104,
        evidence_id="EV-BI-MISSING",
        file_name="unknown_log.log",
        file_type="LOG",
        file_size=1024,
        file_path="uploads/evidence/104/unknown_log.log"
    )
    db_session.add_all([ev1, ev2])
    db_session.commit()

    external_inputs = {
        "EV-BI-ZERO": {
            "behavioural_intelligence": 0.0,
            "semantic_intelligence": 0.2
        },
        "EV-BI-MISSING": {
            "semantic_intelligence": 0.2
            # BI missing
        }
    }

    res = process_case_epra(db_session, case_id=104, current_user=expert, demo_mode=True, external_inputs=external_inputs)
    assert res["status"] == "SUCCESS"

    r_zero = next(r for r in res["results"] if r["evidence_id"] == "EV-BI-ZERO")
    r_missing = next(r for r in res["results"] if r["evidence_id"] == "EV-BI-MISSING")

    # Measured zero: persists as 0.0, not pending
    assert r_zero["behaviour_intelligence"] == 0.0
    assert not any("behaviour" in p.lower() for p in r_zero["pending_external_inputs"])

    # Missing: persists as None (NULL), pending input flagged
    assert r_missing["behaviour_intelligence"] is None
    assert any("behaviour" in p.lower() for p in r_missing["pending_external_inputs"])


# ==============================================================================
# TEST G: DYNAMIC CASE EPRA SUMMARY
# ==============================================================================

def test_g_dynamic_case_epra_summary():
    """
    Verify dynamic summary metric calculations:
    - Coverage percentage == (complete / total) * 100
    - Priority breakdown counts across all 5 tiers
    - Mean, min, max score math
    - Priority queue ordered by rank ascending
    - Score distribution partitions correctly
    """
    mock_results = [
        {"evidence_id": "E1", "rank": 1, "epra_score": 92.5, "priority": "CRITICAL", "analysis_status": "COMPLETE"},
        {"evidence_id": "E2", "rank": 2, "epra_score": 78.0, "priority": "HIGH", "analysis_status": "COMPLETE"},
        {"evidence_id": "E3", "rank": 3, "epra_score": 55.0, "priority": "MEDIUM", "analysis_status": "PARTIAL / PENDING INPUTS"},
        {"evidence_id": "E4", "rank": 4, "epra_score": 30.0, "priority": "LOW", "analysis_status": "PARTIAL / PENDING INPUTS"},
        {"evidence_id": "E5", "rank": 5, "epra_score": 15.0, "priority": "VERY LOW", "analysis_status": "PARTIAL / PENDING INPUTS"},
    ]
    total_ev = 6  # 5 analyzed, 1 pending analysis

    summary = calculate_summary_metrics(total_evidence_count=total_ev, results=mock_results)

    assert summary["total_evidence"] == 6
    assert summary["analyzed_evidence"] == 5
    assert summary["complete_analysis"] == 2
    assert summary["partial_analysis"] == 3
    assert summary["pending_analysis"] == 1
    # Coverage: (2 / 6) * 100 = 33.33%
    assert summary["coverage_percentage"] == round((2 / 6) * 100, 2)

    # Check 5 priority tiers
    assert summary["priority_breakdown"]["CRITICAL"] == 1
    assert summary["priority_breakdown"]["HIGH"] == 1
    assert summary["priority_breakdown"]["MEDIUM"] == 1
    assert summary["priority_breakdown"]["LOW"] == 1
    assert summary["priority_breakdown"]["VERY LOW"] == 1

    # Arithmetic mean: (92.5 + 78.0 + 55.0 + 30.0 + 15.0) / 5 = 270.5 / 5 = 54.1
    assert summary["average_epra_score"] == 54.1
    assert summary["highest_score"] == 92.5
    assert summary["lowest_score"] == 15.0

    # Priority queue: sorted by rank ascending (rank 1 first)
    ranks = [item["rank"] for item in summary["priority_queue"]]
    assert ranks == sorted(ranks)
    assert summary["priority_queue"][0]["evidence_id"] == "E1"

    # Score distribution:
    dist = summary["score_distribution"]
    assert dist["90-100"] == 1
    assert dist["75-90"] == 1
    assert dist["50-75"] == 1
    assert dist["25-50"] == 1
    assert dist["0-25"] == 1


# ==============================================================================
# TEST H: EVIDENCE RANKER: GENUINE RANK DERIVATION
# ==============================================================================

def test_h_evidence_ranker_genuine_derivation():
    """
    Verify ranks are derived from Janhvi's EvidenceRanker, sorted by score descending,
    independent of evidence_id order, row ID order, or insertion sequence.
    """
    e1 = JanhviEvidence(metadata=JanhviMetadata(file_name="low.txt", extension=".txt", mime_type="text/plain", size=10, absolute_path=""))
    e1.epra_score = 20.0

    e2 = JanhviEvidence(metadata=JanhviMetadata(file_name="top.txt", extension=".txt", mime_type="text/plain", size=10, absolute_path=""))
    e2.epra_score = 98.0

    e3 = JanhviEvidence(metadata=JanhviMetadata(file_name="med.txt", extension=".txt", mime_type="text/plain", size=10, absolute_path=""))
    e3.epra_score = 60.0

    e4 = JanhviEvidence(metadata=JanhviMetadata(file_name="high.txt", extension=".txt", mime_type="text/plain", size=10, absolute_path=""))
    e4.epra_score = 85.0

    ranked = EvidenceRanker.rank([e1, e2, e3, e4])

    assert ranked[0].metadata.file_name == "top.txt"
    assert ranked[0].rank == 1

    assert ranked[1].metadata.file_name == "high.txt"
    assert ranked[1].rank == 2

    assert ranked[2].metadata.file_name == "med.txt"
    assert ranked[2].rank == 3

    assert ranked[3].metadata.file_name == "low.txt"
    assert ranked[3].rank == 4


# ==============================================================================
# TEST I: CROSS-CONSUMER CONSISTENCY
# ==============================================================================

def test_i_cross_consumer_consistency(db_session, tmp_path):
    """
    Verify single evidence item analyzed by EPRA produces matching score, priority,
    and rank across all project consumers:
    1. Cyber Expert EPRA view
    2. Investigator Evidence Analysis
    3. Investigator Single Analysis detail
    4. Technical Report Service data
    5. PDF report generation
    6. Suspect Ranking Service
    7. Admin System Statistics
    """
    expert = make_user(id=305, full_name="Cyber Expert Cross", role_id=3, cyber_cell_id=1)
    investigator = make_user(id=205, full_name="Investigator Cross", role_id=2, cyber_cell_id=1)
    admin = make_user(id=105, full_name="Admin Cross", role_id=1, cyber_cell_id=1)
    db_session.add_all([expert, investigator, admin])

    case = Case(
        id=105,
        case_id="CASE-CROSS-005",
        title="Cross Consumer Consistency Case",
        cyber_expert_id=305,
        investigator_id=205,
        created_by=investigator.id,
        status="Open"
    )
    db_session.add(case)

    # Single evidence item
    ev = Evidence(
        id=208,
        case_id=105,
        evidence_id="EV-CROSS-001",
        file_name="financial_fraud.csv",
        file_type="SPREADSHEET",
        file_size=8192,
        file_path="uploads/evidence/105/financial_fraud.csv"
    )
    db_session.add(ev)
    db_session.commit()

    # Process EPRA
    process_res = process_case_epra(
        db_session,
        case_id=105,
        current_user=expert,
        demo_mode=True,
        external_inputs={"behavioural_intelligence": 0.8, "semantic_intelligence": 0.85}
    )
    assert process_res["status"] == "SUCCESS"
    epra_item = process_res["results"][0]
    expected_score = epra_item["epra_score"]
    expected_priority = epra_item["priority"]
    expected_rank = epra_item["rank"]
    assert expected_rank == 1

    # 1. Cyber Expert view
    ce_detail = get_evidence_epra_detail(db_session, case_id=105, evidence_id=208, current_user=expert)
    assert ce_detail["epra_score"] == expected_score
    assert ce_detail["priority"] == expected_priority
    assert ce_detail["rank"] == expected_rank

    # 2. Investigator Evidence Analysis
    inv_analysis_page = get_investigator_analysis_evidence_repository(db_session, case_identifier=105, current_user=investigator)
    assert inv_analysis_page.total == 1
    inv_item = inv_analysis_page.items[0]
    assert inv_item.epra_score == expected_score
    assert inv_item.priority == expected_priority
    assert inv_item.rank == expected_rank
    assert inv_item.file_type == "SPREADSHEET"

    # 3. Investigator Single Analysis Detail
    inv_single = get_investigator_single_analysis_detail(db_session, case_identifier=105, evidence_identifier=208, current_user=investigator)
    assert inv_single.epra_score == expected_score
    assert inv_single.priority == expected_priority
    assert inv_single.rank == expected_rank
    assert inv_single.evidence_type == "SPREADSHEET"

    # 4. Technical Report Service
    report_data = TechnicalReportService.generate_case_report_data(db_session, case_id="CASE-CROSS-005")
    assert len(report_data["epra_analysis"]) == 1
    rep_epra = report_data["epra_analysis"][0]
    assert rep_epra["epra_score"] == expected_score
    assert rep_epra["priority"] == expected_priority
    assert rep_epra["rank"] == expected_rank
    assert rep_epra["evidence_type"] == "SPREADSHEET"

    # 5. PDF Generation
    pdf_path = PDFService.generate_pdf(report_data, output_directory=str(tmp_path))
    assert Path(pdf_path).exists()
    assert Path(pdf_path).stat().st_size > 0

    # 6. Suspect Ranking Service (integrates evidence priority and canonical type)
    suspect = PossibleEntity(
        id=501,
        case_id=105,
        suspect_id="SUSP-001",
        suspect_name="John Doe",
        entity_type="OTHER",
        rank=1,
        confidence_score=0.7
    )
    db_session.add(suspect)
    db_session.flush()
    link = PossibleEntityEvidenceLink(entity_id=501, evidence_id=208)
    db_session.add(link)
    db_session.commit()

    suspect_detail = get_possible_entity_detail(db_session, case=case, entity_identifier=501)
    assert len(suspect_detail.linked_evidence) == 1
    assert suspect_detail.linked_evidence[0].evidence_id == "EV-CROSS-001"
    assert suspect_detail.linked_evidence[0].file_type == "SPREADSHEET"
    assert suspect_detail.linked_evidence[0].epra_score == expected_score
    assert suspect_detail.linked_evidence[0].priority == expected_priority

    # 7. Admin System Statistics
    admin_epra_stats = AdminSystemStatisticsService.get_epra_statistics(db_session, current_user=admin)
    assert admin_epra_stats.total_evidence == 1
    assert admin_epra_stats.highest_score == expected_score
    norm_prio = expected_priority.replace("_", " ")
    assert admin_epra_stats.priority_distribution[norm_prio] == 1


# ==============================================================================
# TEST J: AUTH & CROSS-CASE ISOLATION
# ==============================================================================

def test_j_auth_and_cross_case_isolation(db_session):
    """
    Verify security, authorization, and multi-tenant isolation:
    1. Cyber Expert cannot process or access unassigned case.
    2. Non-expert (Investigator) cannot process EPRA.
    3. Investigator cannot read EPRA of unassigned case.
    4. Cyber Cell scoping limits Admin Stats to current_user.cyber_cell_id.
    5. EPRA scores and ranks from Case A never leak into Case B.
    """
    # Two Cities and Cyber Cells
    city1 = City(id=10, city_name="Cell City Alpha")
    city2 = City(id=20, city_name="Cell City Beta")
    db_session.add_all([city1, city2])
    db_session.flush()

    cell_a = CyberCell(id=10, cyber_cell_name="Cell Alpha", admin_email="admin_a@cell.gov", city_id=10)
    cell_b = CyberCell(id=20, cyber_cell_name="Cell Beta", admin_email="admin_b@cell.gov", city_id=20)
    db_session.add_all([cell_a, cell_b])
    db_session.flush()

    # Users in Cell Alpha
    expert_a = make_user(id=310, full_name="Expert Alpha", role_id=3, cyber_cell_id=10)
    inv_a = make_user(id=210, full_name="Investigator Alpha", role_id=2, cyber_cell_id=10)
    admin_a = make_user(id=110, full_name="Admin Alpha", role_id=1, cyber_cell_id=10)

    # Users in Cell Beta
    expert_b = make_user(id=320, full_name="Expert Beta", role_id=3, cyber_cell_id=20)
    inv_b = make_user(id=220, full_name="Investigator Beta", role_id=2, cyber_cell_id=20)
    admin_b = make_user(id=120, full_name="Admin Beta", role_id=1, cyber_cell_id=20)
    db_session.add_all([expert_a, inv_a, admin_a, expert_b, inv_b, admin_b])

    # Case A in Cell Alpha
    case_a = Case(id=110, case_id="CASE-ALPHA-110", title="Alpha Case", cyber_expert_id=310, investigator_id=210, created_by=inv_a.id, status="Open")
    # Case B in Cell Beta
    case_b = Case(id=120, case_id="CASE-BETA-120", title="Beta Case", cyber_expert_id=320, investigator_id=220, created_by=inv_b.id, status="Open")
    db_session.add_all([case_a, case_b])

    ev_a = Evidence(id=210, case_id=110, evidence_id="EV-A-01", file_name="alpha.pdf", file_type="PDF", file_size=1024, file_path="uploads/evidence/110/alpha.pdf")
    ev_b = Evidence(id=220, case_id=120, evidence_id="EV-B-01", file_name="beta.pdf", file_type="PDF", file_size=1024, file_path="uploads/evidence/120/beta.pdf")
    db_session.add_all([ev_a, ev_b])
    db_session.commit()

    # Process Case A with expert A
    process_case_epra(db_session, case_id=110, current_user=expert_a, demo_mode=True)

    # 1. Expert B cannot access Case A
    with pytest.raises(HTTPException) as exc_info:
        authorize_cyber_expert_case_access(db_session, case_id=110, current_user=expert_b)
    assert exc_info.value.status_code == 403

    # 2. Investigator A cannot process EPRA
    with pytest.raises(HTTPException) as exc_info:
        authorize_cyber_expert_case_access(db_session, case_id=110, current_user=inv_a)
    assert exc_info.value.status_code == 403

    # 3. Investigator B cannot read EPRA of Case A
    with pytest.raises(HTTPException) as exc_info:
        authorize_epra_read_case_access(db_session, case_id=110, current_user=inv_b)
    assert exc_info.value.status_code == 403

    # 4. Investigator A CAN read EPRA of assigned Case A
    allowed_case = authorize_epra_read_case_access(db_session, case_id=110, current_user=inv_a)
    assert allowed_case.id == 110

    # 5. Cyber Cell Scoping in Admin Stats: Admin B must see 0 analyzed evidence from Cell Alpha
    stats_b = AdminSystemStatisticsService.get_epra_statistics(db_session, current_user=admin_b)
    assert stats_b.total_evidence == 1  # only ev_b
    assert stats_b.analyzed_evidence == 0  # ev_b not yet analyzed

    # 6. Case isolation: Case B ranked evidence query returns 0 items
    ranked_b = get_case_ranked_evidence(db_session, case_id=120, current_user=expert_b)
    assert len(ranked_b) == 0
