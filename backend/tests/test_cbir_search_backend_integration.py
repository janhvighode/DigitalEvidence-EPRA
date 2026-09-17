"""
============================================================
Digital Evidence EPRA - Member-3 CBIR Integration Tests
File: test_cbir_search_backend_integration.py
Scope: Text Search, Context Search, Unified Search
Backend Integration, Case Isolation, Authorization, Dynamic Cases
============================================================
"""

import os
import sys
from pathlib import Path
import pytest
from starlette.testclient import TestClient

BACKEND_DIR = Path(__file__).resolve().parent.parent
PROJECT_ROOT = BACKEND_DIR.parent

for p in [str(PROJECT_ROOT), str(BACKEND_DIR)]:
    if p not in sys.path:
        sys.path.insert(0, p)

from app.main import app
from database.database import SessionLocal, engine
from models.user import User
from models.case import Case
from models.evidence import Evidence
from models.evidence_record import EvidenceRecord
from models.possible_entity import PossibleEntity, PossibleEntityEvidenceLink
from models.evidence_link import EvidenceLink
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
    # Find or mock Cyber Expert
    user = db_session.query(User).filter(User.role_id == 3).first()
    if not user:
        user = User(
            full_name="Cyber Expert Test",
            email="cyber_expert_cbir_test@example.com",
            phone_number="9999900003",
            role_id=3
        )
        db_session.add(user)
        db_session.commit()
        db_session.refresh(user)
    return create_access_token(data={"user_id": user.id, "sub": str(user.id), "role_id": 3}), user


@pytest.fixture(scope="module")
def investigator_token(db_session):
    # Find or mock Investigator
    user = db_session.query(User).filter(User.role_id == 2).first()
    if not user:
        user = User(
            full_name="Investigator Test",
            email="investigator_cbir_test@example.com",
            phone_number="9999900002",
            role_id=2
        )
        db_session.add(user)
        db_session.commit()
        db_session.refresh(user)
    return create_access_token(data={"user_id": user.id, "sub": str(user.id), "role_id": 2}), user


class TestCBIRSearchBackendIntegration:

    def test_01_text_search_live_case_post(self, client):
        """Verify text search POST endpoint on real DEPS case (CASE-6922) with arbitrary keyword."""
        resp = client.post(
            "/cases/CASE-6922/cbir/search/text",
            json={"query_text": "phishing", "top_k": 5}
        )
        assert resp.status_code == 200, f"Expected 200, got {resp.status_code}: {resp.text}"
        data = resp.json()
        assert data["status"] == "Success"
        assert data["case_id"] == "CASE-6922"
        assert data["search_query"] == "phishing"
        assert data["results_count"] >= 1
        assert len(data["results"]) >= 1
        assert any("phishing" in str(r.get("filename_or_name", "")).lower() or "phishing" in str(r.get("matched_value", "")).lower() for r in data["results"])

    def test_02_text_search_live_case_get(self, client):
        """Verify text search GET endpoint on real DEPS case."""
        resp = client.get(
            "/cases/CASE-6922/cbir/search/text?query_text=ransomware&top_k=5"
        )
        assert resp.status_code == 200, f"Expected 200, got {resp.status_code}: {resp.text}"
        data = resp.json()
        assert data["status"] == "Success"
        assert data["case_id"] == "CASE-6922"
        assert data["results_count"] >= 1
        assert any("ransomware" in str(r.get("filename_or_name", "")).lower() for r in data["results"])

    def test_03_context_search_graph_path(self, client):
        """Verify context search traverses genuine relationship graph and returns multi-hop paths."""
        resp = client.post(
            "/cases/CASE-6922/cbir/search/context",
            json={"query_text": "secure-bank", "max_hops": 2, "top_k": 5}
        )
        assert resp.status_code == 200, f"Expected 200, got {resp.status_code}: {resp.text}"
        data = resp.json()
        assert data["status"] == "Success"
        assert data["case_id"] == "CASE-6922"
        assert data["results_count"] >= 2
        # Check that anchor and related evidence/entities are returned with relationship_path
        paths = [r.get("relationship_path") for r in data["results"] if r.get("relationship_path")]
        assert len(paths) >= 2
        assert any("Anchor" in p for p in paths)
        assert any("ASSOCIATED_WITH" in p for p in paths)

    def test_04_context_search_get(self, client):
        """Verify context search GET endpoint."""
        resp = client.get(
            "/cases/CASE-6922/cbir/search/context?query_text=victim&max_hops=2&top_k=5"
        )
        assert resp.status_code == 200, f"Expected 200, got {resp.status_code}: {resp.text}"
        data = resp.json()
        assert data["status"] == "Success"
        assert data["results_count"] >= 1

    def test_05_unified_search_post(self, client):
        """Verify unified search POST endpoint for text and hybrid query types."""
        resp = client.post(
            "/cases/CASE-6922/cbir/search/unified",
            json={"query_text": "bank", "search_mode": "text", "top_k": 5}
        )
        assert resp.status_code == 200, f"Expected 200, got {resp.status_code}: {resp.text}"
        data = resp.json()
        assert data["status"] == "Success"
        assert data["case_id"] == "CASE-6922"
        assert data["results_count"] >= 1
        assert "ranked_evidence" in data
        assert "graph" in data

    def test_06_unified_search_get(self, client):
        """Verify unified search GET endpoint."""
        resp = client.get(
            "/cases/CASE-6922/cbir/search/unified?query_text=laptop&search_mode=text&top_k=5"
        )
        assert resp.status_code == 200, f"Expected 200, got {resp.status_code}: {resp.text}"
        data = resp.json()
        assert data["status"] == "Success"
        assert data["results_count"] >= 1

    def test_07_clean_no_result_behavior(self, client):
        """Non-matching arbitrary keywords must cleanly return status='no_data_found' with 0 results and HTTP 200."""
        resp = client.post(
            "/cases/CASE-6922/cbir/search/text",
            json={"query_text": "xyznonexistentkeyword12345", "top_k": 5}
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["status"] == "no_data_found"
        assert data["results_count"] == 0
        assert data["results"] == []

    def test_08_empty_query_behavior(self, client):
        """Empty query string must return status='no_data_found' without 422 or 500 error."""
        resp = client.post(
            "/cases/CASE-6922/cbir/search/text",
            json={"query_text": "", "top_k": 5}
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["status"] == "no_data_found"
        assert data["results_count"] == 0

    def test_09_strict_case_isolation(self, client, db_session):
        """Evidence from CASE-6922 must NEVER leak into searches for another case (e.g., CASE-8577)."""
        # Search for 'phishing' in CASE-8577 (which does not have phishing_email.eml)
        resp = client.post(
            "/cases/CASE-8577/cbir/search/text",
            json={"query_text": "phishing", "top_k": 10}
        )
        assert resp.status_code == 200
        data = resp.json()
        ev_ids = [r.get("evidence_id") for r in data.get("results", [])]
        assert "EV-6922-005" not in ev_ids, "Cross-case evidence leak detected!"

    def test_10_authorization_assigned_cyber_expert(self, client, db_session, cyber_expert_token):
        """Assigned cyber expert with valid JWT is authorized to search."""
        token, user = cyber_expert_token
        # Assign cyber expert to case CASE-6922
        case = db_session.query(Case).filter(Case.case_id == "CASE-6922").first()
        if case:
            case.cyber_expert_id = user.id
            db_session.commit()

        resp = client.post(
            "/cases/CASE-6922/cbir/search/text",
            json={"query_text": "phishing", "top_k": 5},
            headers={"Authorization": f"Bearer {token}"}
        )
        assert resp.status_code == 200

    def test_11_authorization_unassigned_user_forbidden(self, client, db_session, cyber_expert_token):
        """Cyber expert not assigned to a case must receive HTTP 403 Forbidden."""
        token, user = cyber_expert_token
        # Unassign user from CASE-8577
        case = db_session.query(Case).filter(Case.case_id == "CASE-8577").first()
        if case:
            case.cyber_expert_id = 999999
            db_session.commit()

        resp = client.post(
            "/cases/CASE-8577/cbir/search/text",
            json={"query_text": "evidence", "top_k": 5},
            headers={"Authorization": f"Bearer {token}"}
        )
        assert resp.status_code == 403, f"Expected 403 Forbidden, got {resp.status_code}"

    def test_12_dynamic_new_case_and_new_evidence(self, client, db_session):
        """A dynamically created new case with new evidence must be searchable without hardcoding."""
        dyn_case_id = "CASE-DYN-AUTO-999"
        # Cleanup if exists
        old_case = db_session.query(Case).filter(Case.case_id == dyn_case_id).first()
        if old_case:
            old_ev_ids = [e.id for e in db_session.query(Evidence).filter(Evidence.case_id == old_case.id).all()]
            for p in db_session.query(PossibleEntityEvidenceLink).all():
                if p.evidence_id in old_ev_ids:
                    db_session.delete(p)
            db_session.commit()
            for ent in db_session.query(PossibleEntity).filter(PossibleEntity.case_id == old_case.id).all():
                db_session.delete(ent)
            db_session.commit()
            for ev in db_session.query(Evidence).filter(Evidence.case_id == old_case.id).all():
                db_session.delete(ev)
            db_session.commit()
            db_session.delete(old_case)
            db_session.commit()

        new_case = Case(
            case_id=dyn_case_id,
            title="Dynamic Automated Forensic Case",
            description="Dynamically created case for integration testing",
            status="Open",
            priority="High"
        )
        db_session.add(new_case)
        db_session.commit()
        db_session.refresh(new_case)

        new_ev1 = Evidence(
            case_id=new_case.id,
            evidence_id="EV-DYN-999-01",
            file_name="secret_financial_audit.xlsx",
            file_type="Spreadsheet",
            file_size=10240,
            file_path="uploads/secret_financial_audit.xlsx",
            status="Active"
        )
        new_ev2 = Evidence(
            case_id=new_case.id,
            evidence_id="EV-DYN-999-02",
            file_name="suspect_confession_audio.wav",
            file_type="Audio",
            file_size=20480,
            file_path="uploads/suspect_confession_audio.wav",
            status="Active"
        )
        db_session.add(new_ev1)
        db_session.add(new_ev2)
        db_session.commit()
        db_session.refresh(new_ev1)
        db_session.refresh(new_ev2)

        # Also add dynamic entity
        entity = PossibleEntity(
            case_id=new_case.id,
            suspect_id="SUSPECT-DYN-01",
            suspect_name="alister_crowley@darknet.org",
            entity_type="EMAIL",
            rank=1,
            total_epra_score=75.5,
            confidence_score=0.92
        )
        db_session.add(entity)
        db_session.commit()
        db_session.refresh(entity)

        pel = PossibleEntityEvidenceLink(
            entity_id=entity.id,
            evidence_id=new_ev1.id
        )
        db_session.add(pel)
        db_session.commit()

        try:
            # 1. Test Text Search on dynamic case
            t_resp = client.post(
                f"/cases/{dyn_case_id}/cbir/search/text",
                json={"query_text": "financial", "top_k": 5}
            )
            assert t_resp.status_code == 200
            t_data = t_resp.json()
            assert t_data["status"] == "Success"
            assert t_data["results_count"] == 1
            assert t_data["results"][0]["evidence_id"] == "EV-DYN-999-01"

            # 2. Test Context Search on dynamic case
            c_resp = client.post(
                f"/cases/{dyn_case_id}/cbir/search/context",
                json={"query_text": "alister", "max_hops": 2, "top_k": 5}
            )
            assert c_resp.status_code == 200
            c_data = c_resp.json()
            assert c_data["status"] == "Success"
            assert c_data["results_count"] >= 1
            ids = [r["evidence_id"] for r in c_data["results"]]
            assert "alister_crowley@darknet.org" in ids or "EV-DYN-999-01" in ids

            # 3. Test Unified Search on dynamic case
            u_resp = client.post(
                f"/cases/{dyn_case_id}/cbir/search/unified",
                json={"query_text": "confession", "search_mode": "text", "top_k": 5}
            )
            assert u_resp.status_code == 200
            u_data = u_resp.json()
            assert u_data["status"] == "Success"
            assert u_data["results_count"] >= 1

        finally:
            # Cleanup dynamic test case in proper FK dependency order
            try:
                db_session.delete(pel)
                db_session.commit()
            except Exception:
                db_session.rollback()
            try:
                db_session.delete(entity)
                db_session.commit()
            except Exception:
                db_session.rollback()
            try:
                db_session.delete(new_ev1)
                db_session.delete(new_ev2)
                db_session.commit()
            except Exception:
                db_session.rollback()
            try:
                db_session.delete(new_case)
                db_session.commit()
            except Exception:
                db_session.rollback()
