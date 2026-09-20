"""
============================================================
Digital Evidence EPRA - CBIR Unified Search & Content Tests
File: test_cbir_unified_search_fix.py
Scope: Tests A through N covering Unified Search integration,
       All Modalities mapping, case isolation, authorization,
       deduplication, genuine scores without fake visual signals,
       and generic evidence content/preview serving.
============================================================
"""

import os
import sys
import tempfile
from pathlib import Path
import pytest
from starlette.testclient import TestClient

BACKEND_DIR = Path(__file__).resolve().parent.parent
PROJECT_ROOT = BACKEND_DIR.parent

for p in [str(PROJECT_ROOT), str(BACKEND_DIR)]:
    if p not in sys.path:
        sys.path.insert(0, p)

from app.main import app
from database.database import SessionLocal
from models.user import User
from models.case import Case
from models.evidence import Evidence
from models.evidence_record import EvidenceRecord
from utils.jwt_handler import create_access_token


@pytest.fixture(scope="module")
def client():
    return TestClient(app)


@pytest.fixture(scope="module")
def db_session():
    db = SessionLocal()
    yield db
    db.close()


@pytest.fixture(scope="module")
def cyber_expert_token(db_session):
    user = db_session.query(User).filter(User.role_id == 3).first()
    return create_access_token(data={"user_id": user.id, "sub": str(user.id), "role_id": 3}), user


@pytest.fixture(scope="module")
def unauthorized_expert_token(db_session):
    user = db_session.query(User).filter(User.role_id == 3).order_by(User.id.desc()).first()
    return create_access_token(data={"user_id": user.id, "sub": str(user.id), "role_id": 3}), user




class TestCBIRUnifiedSearchAndContent:

    # ------------------------------------------------------------
    # TEST A — TEXT SEARCH BASELINE
    # ------------------------------------------------------------
    def test_a_text_search_baseline(self, client):
        """Case contains text-indexed/image evidence matching 'laptop'. Text Search returns it."""
        resp = client.post(
            "/cases/CASE-6922/cbir/search/text",
            json={"query_text": "laptop", "top_k": 5}
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["status"] == "Success"
        assert data["results_count"] >= 1
        ev_ids = [r.get("evidence_id") for r in data["results"]]
        assert "EV-6922-010" in ev_ids

    # ------------------------------------------------------------
    # TEST B — UNIFIED SEARCH INCLUDES TEXT RESULT
    # ------------------------------------------------------------
    def test_b_unified_search_includes_text_result(self, client):
        """Unified Search 'All Modalities' must include valid text candidate EV-6922-010."""
        # Test with POST
        resp = client.post(
            "/cases/CASE-6922/cbir/search/unified",
            json={"query_text": "laptop", "search_mode": "All Modalities", "top_k": 5}
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["status"] == "Success"
        assert data["results_count"] >= 1
        ev_ids = [r.get("evidence_id") for r in data["results"]]
        assert "EV-6922-010" in ev_ids

        # Verify candidate data
        target = next(r for r in data["results"] if r["evidence_id"] == "EV-6922-010")
        assert target["filename"] == "laptop.jpeg"
        assert target["relevance_score"] >= 0.90
        assert target["match_source"] == "Text Search"

        # Also test with GET
        resp_get = client.get(
            "/cases/CASE-6922/cbir/search/unified?query_text=laptop&search_mode=All%20Modalities&top_k=5"
        )
        assert resp_get.status_code == 200
        data_get = resp_get.json()
        assert data_get["status"] == "Success"
        assert any(r.get("evidence_id") == "EV-6922-010" for r in data_get["results"])

    # ------------------------------------------------------------
    # TEST C — NO MATCH
    # ------------------------------------------------------------
    def test_c_no_match_returns_clean_zero_results(self, client):
        """Query with genuinely no matching evidence returns HTTP 200, status='no_data_found', 0 results."""
        resp = client.post(
            "/cases/CASE-6922/cbir/search/unified",
            json={"query_text": "xyznonexistentquery987654321", "search_mode": "All Modalities", "top_k": 5}
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["status"] == "no_data_found"
        assert data["results_count"] == 0
        assert data["results"] == []

    # ------------------------------------------------------------
    # TEST D — CASE ISOLATION
    # ------------------------------------------------------------
    def test_d_case_isolation(self, client):
        """Evidence belonging to CASE-6922 MUST NOT appear in CASE-8577 search."""
        resp = client.post(
            "/cases/CASE-8577/cbir/search/unified",
            json={"query_text": "laptop", "search_mode": "All Modalities", "top_k": 10}
        )
        assert resp.status_code == 200
        data = resp.json()
        ev_ids = [r.get("evidence_id") for r in data.get("results", [])]
        assert "EV-6922-010" not in ev_ids

    # ------------------------------------------------------------
    # TEST E — USER AUTHORIZATION
    # ------------------------------------------------------------
    def test_e_user_authorization(self, client, db_session, unauthorized_expert_token):
        """Unauthorized user attempting search on an unassigned case receives 403."""
        token, user = unauthorized_expert_token
        # Ensure user is not assigned to CASE-8577
        case = db_session.query(Case).filter(Case.case_id == "CASE-8577").first()
        if case and case.cyber_expert_id == user.id:
            case.cyber_expert_id = None
            db_session.commit()

        resp = client.post(
            "/cases/CASE-8577/cbir/search/unified",
            json={"query_text": "laptop", "search_mode": "All Modalities", "top_k": 5},
            headers={"Authorization": f"Bearer {token}"}
        )
        assert resp.status_code == 403

    # ------------------------------------------------------------
    # TEST F — DEDUPLICATION
    # ------------------------------------------------------------
    def test_f_deduplication(self, client):
        """Evidence returned from multiple modalities is deduplicated by canonical evidence_id."""
        resp = client.post(
            "/cases/CASE-6922/cbir/search/unified",
            json={"query_text": "bank", "search_mode": "All Modalities", "top_k": 10}
        )
        assert resp.status_code == 200
        data = resp.json()
        ev_ids = [r.get("evidence_id") for r in data.get("results", [])]
        # Ensure every evidence_id is unique
        assert len(ev_ids) == len(set(ev_ids))

    # ------------------------------------------------------------
    # TEST G — MISSING MODALITY (DO NOT FAKE VISUAL SCORES)
    # ------------------------------------------------------------
    def test_g_missing_modality_no_fake_visual_scores(self, client):
        """When text signal exists without a visual query image, visual scores must be None."""
        resp = client.post(
            "/cases/CASE-6922/cbir/search/unified",
            json={"query_text": "laptop", "search_mode": "All Modalities", "top_k": 5}
        )
        assert resp.status_code == 200
        data = resp.json()
        target = next(r for r in data["results"] if r["evidence_id"] == "EV-6922-010")
        # Visual scores MUST NOT be fabricated
        assert target["visual_similarity_score"] is None
        assert target["edge_similarity"] is None
        assert target["orb_similarity"] is None
        assert target["color_similarity"] is None
        assert target["grayscale_similarity"] is None
        # But text relevance is genuine
        assert target["relevance_score"] >= 0.90

    # ------------------------------------------------------------
    # TEST H — GENERIC IMAGE CONTENT
    # ------------------------------------------------------------
    def test_h_generic_image_content(self, client, db_session, cyber_expert_token):
        """Canonical evidence content mechanism: 200 + correct Content-Type if binary exists, 404 if binary missing."""
        token, user = cyber_expert_token
        case = db_session.query(Case).filter(Case.case_id == "CASE-6922").first()
        if case:
            case.cyber_expert_id = user.id
            db_session.commit()

        # EV-6922-010 physical binary is historically missing from ephemeral storage -> expected clean 404
        resp_missing = client.get(
            "/cases/CASE-6922/evidence/EV-6922-010/preview",
            headers={"Authorization": f"Bearer {token}"}
        )
        assert resp_missing.status_code == 404
        assert "not found on disk" in resp_missing.json()["detail"] or "not available" in resp_missing.json()["detail"]

        # Now test with a real physical binary dynamically created in persistent storage
        storage_dir = Path("uploads/evidence") / str(case.id)
        storage_dir.mkdir(parents=True, exist_ok=True)
        test_img_path = storage_dir / "test_active_photo.jpg"
        test_img_path.write_bytes(b"\xff\xd8\xff\xe0\x00\x10JFIF\x00\x01\x01\x01\x00`\x00`\x00\x00\xff\xdb\x00C\x00")

        dyn_ev = Evidence(
            case_id=case.id,
            evidence_id="EV-TEST-REAL-BIN",
            file_name="test_active_photo.jpg",
            file_type="Image",
            file_size=len(test_img_path.read_bytes()),
            file_path=f"uploads/evidence/{case.id}/test_active_photo.jpg",
            status="Active"
        )
        db_session.add(dyn_ev)
        db_session.commit()
        db_session.refresh(dyn_ev)

        try:
            # Test /preview endpoint
            resp_preview = client.get(
                f"/cases/CASE-6922/evidence/{dyn_ev.evidence_id}/preview",
                headers={"Authorization": f"Bearer {token}"}
            )
            assert resp_preview.status_code == 200
            assert resp_preview.headers["content-type"] in ["image/jpeg", "image/jpg"]
            assert len(resp_preview.content) > 0

            # Test /content endpoint
            resp_content = client.get(
                f"/cases/CASE-6922/evidence/{dyn_ev.evidence_id}/content",
                headers={"Authorization": f"Bearer {token}"}
            )
            assert resp_content.status_code == 200
            assert resp_content.headers["content-type"] in ["image/jpeg", "image/jpg"]
            assert len(resp_content.content) > 0
        finally:
            db_session.delete(dyn_ev)
            db_session.commit()
            if test_img_path.exists():
                test_img_path.unlink()

    # ------------------------------------------------------------
    # TEST I — WRONG CASE EVIDENCE CONTENT
    # ------------------------------------------------------------
    def test_i_wrong_case_evidence_content(self, client, db_session, cyber_expert_token):
        """Using valid evidence_id from another case must not return content (404/403)."""
        token, user = cyber_expert_token
        # Attempt to access CASE-6922 evidence using CASE-8577 path
        resp = client.get(
            "/cases/CASE-8577/evidence/EV-6922-010/preview",
            headers={"Authorization": f"Bearer {token}"}
        )
        assert resp.status_code in [403, 404]

    # ------------------------------------------------------------
    # TEST J — UNKNOWN EVIDENCE
    # ------------------------------------------------------------
    def test_j_unknown_evidence_clean_not_found(self, client, db_session, cyber_expert_token):
        """Unknown evidence_id returns clean 404."""
        token, user = cyber_expert_token
        resp = client.get(
            "/cases/CASE-6922/evidence/EV-UNKNOWN-999999/preview",
            headers={"Authorization": f"Bearer {token}"}
        )
        assert resp.status_code == 404

    # ------------------------------------------------------------
    # TEST K — NON-IMAGE EVIDENCE CONTENT
    # ------------------------------------------------------------
    def test_k_non_image_evidence_content(self, client, db_session, cyber_expert_token):
        """Generic evidence content mechanism supports PDF and document evidence with correct MIME type."""
        token, user = cyber_expert_token
        case = db_session.query(Case).filter(Case.case_id == "CASE-6922").first()
        storage_dir = Path("uploads/evidence") / str(case.id)
        storage_dir.mkdir(parents=True, exist_ok=True)
        test_pdf_path = storage_dir / "test_report.pdf"
        test_pdf_path.write_bytes(b"%PDF-1.4 test forensic report content")

        dyn_pdf = Evidence(
            case_id=case.id,
            evidence_id="EV-TEST-PDF-01",
            file_name="test_report.pdf",
            file_type="PDF Document",
            file_size=len(test_pdf_path.read_bytes()),
            file_path=f"uploads/evidence/{case.id}/test_report.pdf",
            status="Active"
        )
        db_session.add(dyn_pdf)
        db_session.commit()
        db_session.refresh(dyn_pdf)

        try:
            resp_pdf = client.get(
                f"/cases/CASE-6922/evidence/{dyn_pdf.evidence_id}/content",
                headers={"Authorization": f"Bearer {token}"}
            )
            assert resp_pdf.status_code == 200
            assert resp_pdf.headers["content-type"] == "application/pdf"
            assert resp_pdf.content.startswith(b"%PDF-1.4")
        finally:
            db_session.delete(dyn_pdf)
            db_session.commit()
            if test_pdf_path.exists():
                test_pdf_path.unlink()

    # ------------------------------------------------------------
    # TEST L — CBIR REGRESSION
    # ------------------------------------------------------------
    def test_l_cbir_regression(self, client):
        """Existing CBIR comparison endpoints remain functional and unchanged."""
        resp = client.get("/cases/CASE-6922/cbir/eligible-images")
        assert resp.status_code == 200
        data = resp.json()
        assert "eligible_images" in data
        assert data["eligible_image_count"] >= 1

    # ------------------------------------------------------------
    # TEST M — TEXT SEARCH REGRESSION
    # ------------------------------------------------------------
    def test_m_text_search_regression(self, client):
        """Existing Text Search tests continue to pass without regression."""
        resp = client.post(
            "/cases/CASE-6922/cbir/search/text",
            json={"query_text": "phishing", "top_k": 5}
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["status"] == "Success"
        assert data["results_count"] >= 1

    # ------------------------------------------------------------
    # TEST N — CONTEXT / RELATIONSHIP REGRESSION
    # ------------------------------------------------------------
    def test_n_context_relationship_regression(self, client):
        """Context Search and relationship graph engine continue to operate without regression."""
        resp = client.post(
            "/cases/CASE-6922/cbir/search/context",
            json={"query_text": "secure-bank", "max_hops": 2, "top_k": 5}
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["status"] == "Success"
        assert data["results_count"] >= 1
