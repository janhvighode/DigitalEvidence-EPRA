import os
import sys
import subprocess
from pathlib import Path
from datetime import datetime

# Add project root and backend dir to sys.path
root_dir = Path(__file__).resolve().parent.parent.parent
if str(root_dir) not in sys.path:
    sys.path.insert(0, str(root_dir))
backend_dir = Path(__file__).resolve().parent.parent
if str(backend_dir) not in sys.path:
    sys.path.insert(0, str(backend_dir))

from fastapi import HTTPException
from database.database import SessionLocal, engine, Base
from models.user import User
from models.case import Case
from models.evidence import Evidence
from models.evidence_hash import EvidenceHash
from models.epra_result import EPRAResult

from ai_modules.epra_v2.models.evidence import Evidence as JanhviEvidence
from ai_modules.epra_v2.models.metadata import Metadata as JanhviMetadata
from ai_modules.epra_v2.services.epra_service import EPRAService
from ai_modules.epra_v2.ranking.evidence_ranker import EvidenceRanker

from services.epra_service import (
    authorize_cyber_expert_case_access,
    process_case_epra,
    get_case_epra_summary,
    get_case_ranked_evidence,
    get_evidence_epra_detail,
    calculate_summary_metrics
)
from routes.epra_routes import router as epra_router


def test_1_epra_module_imports_and_engine_integrity():
    """Verify Janhvi's EPRA v2 module imports and core classes operate properly."""
    meta = JanhviMetadata(
        file_name="phishing_email.eml",
        extension=".eml",
        mime_type="message/rfc822",
        size=1024,
        absolute_path="",
        evidence_type="EMAIL"
    )
    ev = JanhviEvidence(metadata=meta)
    assert ev.metadata.file_name == "phishing_email.eml"

    processed = EPRAService.process(ev, [], demo_mode=True)
    assert processed.processed is True
    assert processed.epra_score > 0.0
    assert processed.priority in ["CRITICAL", "HIGH", "MEDIUM", "LOW", "VERY LOW"]
    print("PASS: test_1_epra_module_imports_and_engine_integrity")


def test_2_routes_registered_and_endpoints_correct():
    """Verify all 4 EPRA endpoints are mounted with correct HTTP methods."""
    routes = {r.path: r.methods for r in epra_router.routes}
    assert "/cases/{case_id}/epra/process" in routes
    assert "POST" in routes["/cases/{case_id}/epra/process"]

    assert "/cases/{case_id}/epra/summary" in routes
    assert "GET" in routes["/cases/{case_id}/epra/summary"]

    assert "/cases/{case_id}/epra/evidence" in routes
    assert "GET" in routes["/cases/{case_id}/epra/evidence"]

    assert "/cases/{case_id}/epra/evidence/{evidence_id}" in routes
    assert "GET" in routes["/cases/{case_id}/epra/evidence/{evidence_id}"]
    print("PASS: test_2_routes_registered_and_endpoints_correct")


def test_3_cyber_expert_authorization_security():
    """Verify strict Cyber Expert authorization enforcement (role_id == 3 and case assignment)."""
    db = SessionLocal()
    try:
        # 1. Non-Cyber Expert (role_id == 2 or 1) must be rejected with 403
        fake_investigator = User(id=9991, role_id=2, full_name="Investigator User")
        try:
            authorize_cyber_expert_case_access(db, "C-9999999", fake_investigator)
            assert False, "Should have raised 403 for non-cyber expert"
        except HTTPException as e:
            assert e.status_code == 403
            assert "Cyber Expert access required" in e.detail

        # 2. Cyber Expert trying to access unassigned case must be rejected with 403
        expert_a = User(id=8881, role_id=3, full_name="Expert A")
        # Find or create a test case assigned to someone else
        test_case = db.query(Case).filter(Case.cyber_expert_id != 8881).first()
        if test_case:
            try:
                authorize_cyber_expert_case_access(db, test_case.id, expert_a)
                assert False, "Should have raised 403 for unassigned case"
            except HTTPException as e:
                assert e.status_code == 403
                assert "Access denied" in e.detail

        # 3. Non-existent case must return 404
        expert_b = User(id=8882, role_id=3, full_name="Expert B")
        try:
            authorize_cyber_expert_case_access(db, "NON_EXISTENT_CASE_999999", expert_b)
            assert False, "Should have raised 404"
        except HTTPException as e:
            assert e.status_code == 404
    finally:
        db.close()
    print("PASS: test_3_cyber_expert_authorization_security")


def test_4_image_semantic_pending_rule():
    """Verify Critical SI Rule: Missing IMAGE semantic score yields null, PENDING status, and partial analysis."""
    db = SessionLocal()
    try:
        # Create a test case assigned to test cyber expert
        expert = db.query(User).filter(User.role_id == 3).first()
        if not expert:
            expert = User(id=8880, full_name="Test Cyber Expert", username="test_expert", role_id=3)
            db.add(expert)
            db.commit()

        test_case = db.query(Case).filter(Case.cyber_expert_id == expert.id).first()
        if not test_case:
            test_case = Case(
                case_id="TEST-EPRA-CASE-1",
                title="Investigation of Suspect Breach",
                description="Analysis of suspect digital images and documents",
                cyber_expert_id=expert.id,
                status="Open",
                priority="Medium"
            )
            db.add(test_case)
            db.commit()

        # Add an IMAGE evidence record without Member 3 score
        img_ev = db.query(Evidence).filter(
            Evidence.case_id == test_case.id,
            Evidence.file_name == "test_crime_scene.jpg"
        ).first()
        if not img_ev:
            img_ev = Evidence(
                evidence_id="EV-TEST-IMG-001",
                case_id=test_case.id,
                file_name="test_crime_scene.jpg",
                file_type="IMAGE",
                file_size=204800,
                file_path="uploads/test_crime_scene.jpg",
                status="Active"
            )
            db.add(img_ev)
            db.commit()

        # Add associated hash record
        h_rec = db.query(EvidenceHash).filter(EvidenceHash.evidence_id == img_ev.id).first()
        if not h_rec:
            h_rec = EvidenceHash(
                evidence_id=img_ev.id,
                file_name=img_ev.file_name,
                sha256_hash="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
                current_hash="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
                original_hash="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
                hash_match=True,
                tampered=False,
                integrity_status="Verified"
            )
            db.add(h_rec)
            db.commit()

        # Execute EPRA processing without external inputs
        response = process_case_epra(db, test_case, expert, external_inputs=None, demo_mode=False)

        # Locate img_ev in results
        img_res = next((r for r in response["ranked_evidence"] if r["evidence_id"] == img_ev.evidence_id), None)
        assert img_res is not None, "Image evidence must be processed and ranked"
        assert img_res["semantic_intelligence"] is None, "Missing IMAGE score must be null"
        assert img_res["semantic_status"] == "PENDING", "Status must be PENDING"
        assert "Awaiting IMAGE CBIR/Semantic score" in img_res["pending_external_inputs"]
        assert img_res["analysis_status"] == "PARTIAL / PENDING INPUTS"
        assert img_res["hash_verified"] is True
    finally:
        db.close()
    print("PASS: test_4_image_semantic_pending_rule")


def test_5_real_measured_zero_semantic_score():
    """Verify Critical SI Rule: Real calculated semantic value of 0.0000 remains 0.0000 and MEASURED."""
    db = SessionLocal()
    try:
        expert = db.query(User).filter(User.role_id == 3).first()
        test_case = db.query(Case).filter(Case.cyber_expert_id == expert.id).first()
        img_ev = db.query(Evidence).filter(
            Evidence.case_id == test_case.id,
            Evidence.file_name == "test_crime_scene.jpg"
        ).first()

        # Supply genuine Member 3 score of 0.0
        ext_inputs = {
            img_ev.evidence_id: {
                "semantic_score": 0.0
            }
        }

        response = process_case_epra(db, test_case, expert, external_inputs=ext_inputs, demo_mode=False)
        img_res = next((r for r in response["ranked_evidence"] if r["evidence_id"] == img_ev.evidence_id), None)

        assert img_res is not None
        assert img_res["semantic_intelligence"] == 0.0, "Measured zero must remain 0.0"
        assert img_res["semantic_status"] == "MEASURED", "Status must be MEASURED when supplied"
        assert "Awaiting IMAGE CBIR/Semantic score" not in img_res["pending_external_inputs"]
    finally:
        db.close()
    print("PASS: test_5_real_measured_zero_semantic_score")


def test_6_dynamic_summary_consistency_and_top_evidence():
    """Verify summary counts, distribution, and top evidence are dynamically derived and consistent."""
    case = Case(id=101, case_id="C-TEST-SUMMARY", title="Summary Test Case")
    sample_results = [
        {"rank": 1, "evidence_id": "EV-001", "epra_score": 92.5, "priority": "CRITICAL"},
        {"rank": 2, "evidence_id": "EV-002", "epra_score": 81.0, "priority": "HIGH"},
        {"rank": 3, "evidence_id": "EV-003", "epra_score": 65.0, "priority": "MEDIUM"},
        {"rank": 4, "evidence_id": "EV-004", "epra_score": 55.0, "priority": "MEDIUM"},
        {"rank": 5, "evidence_id": "EV-005", "epra_score": 35.0, "priority": "LOW"},
        {"rank": 6, "evidence_id": "EV-006", "epra_score": 15.0, "priority": "VERY LOW"},
    ]
    total_in_case = 10  # 6 analyzed + 4 pending

    summary = calculate_summary_metrics(case, total_in_case, sample_results)

    assert summary["case_id"] == "C-TEST-SUMMARY"
    assert summary["total_evidence"] == 10
    assert summary["critical"] == 1
    assert summary["high"] == 1
    assert summary["medium"] == 2
    assert summary["low"] == 1
    assert summary["very_low"] == 1
    assert summary["pending_analysis"] == 4

    # Mathematical consistency rule:
    # total_evidence == critical + high + medium + low + very_low + pending_analysis
    sum_all = (
        summary["critical"]
        + summary["high"]
        + summary["medium"]
        + summary["low"]
        + summary["very_low"]
        + summary["pending_analysis"]
    )
    assert sum_all == summary["total_evidence"]

    # Top evidence derivation
    assert len(summary["top_evidence"]) == 5
    assert summary["top_evidence"][0]["evidence_id"] == "EV-001"
    assert summary["top_evidence"][0]["rank"] == 1
    print("PASS: test_6_dynamic_summary_consistency_and_top_evidence")


def test_7_evidence_epra_detail_retrieval():
    """Verify single evidence detail endpoint logic."""
    db = SessionLocal()
    try:
        expert = db.query(User).filter(User.role_id == 3).first()
        test_case = db.query(Case).filter(Case.cyber_expert_id == expert.id).first()
        img_ev = db.query(Evidence).filter(Evidence.case_id == test_case.id).first()

        detail = get_evidence_epra_detail(db, test_case, img_ev.evidence_id)
        assert detail["evidence_id"] == img_ev.evidence_id
        assert "epra_score" in detail
        assert "ipi" in detail
        assert "priority" in detail
        assert "rank" in detail
        assert "semantic_status" in detail
        assert "authenticity_risk" in detail
        assert "context_intelligence" in detail
        assert "behaviour_intelligence" in detail
        assert "investigative_intelligence" in detail
    finally:
        db.close()
    print("PASS: test_7_evidence_epra_detail_retrieval")


def test_8_no_frontend_files_touched():
    """Verify git status shows ZERO modifications or additions inside frontend/."""
    out = subprocess.check_output(["git", "status", "--porcelain", "frontend/"]).decode("utf-8")
    assert out.strip() == "", f"Frontend directory must be untouched! Found changes:\n{out}"
    print("PASS: test_8_no_frontend_files_touched")


if __name__ == "__main__":
    print("\n--- RUNNING EPRA BACKEND INTEGRATION TESTS ---")
    test_1_epra_module_imports_and_engine_integrity()
    test_2_routes_registered_and_endpoints_correct()
    test_3_cyber_expert_authorization_security()
    test_4_image_semantic_pending_rule()
    test_5_real_measured_zero_semantic_score()
    test_6_dynamic_summary_consistency_and_top_evidence()
    test_7_evidence_epra_detail_retrieval()
    test_8_no_frontend_files_touched()
    print("\nALL 8 INTEGRATION TESTS PASSED SUCCESSFULLY!")
