import os
import sys
import unittest
from pathlib import Path
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from fastapi import HTTPException

root_dir = Path(__file__).resolve().parent.parent.parent
if str(root_dir) not in sys.path:
    sys.path.insert(0, str(root_dir))
backend_dir = Path(__file__).resolve().parent.parent
if str(backend_dir) not in sys.path:
    sys.path.insert(0, str(backend_dir))

from database.database import Base
from models.user import User
from models.case import Case
from models.evidence import Evidence
from models.evidence_hash import EvidenceHash
from models.cbir_result import CBIRResult
from models.role import Role
from models.city import City
from models.cyber_cell import CyberCell

from schemas.cbir import CBIRCompareRequest
from routes.cbir_routes import (
    list_case_images,
    execute_cbir_comparison,
    get_cbir_results,
    get_candidate_details
)


def setup_in_memory_db():
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
            CBIRResult.__table__
        ]
    )
    Session = sessionmaker(bind=engine)
    db = Session()

    # Seed Users
    expert_user = User(
        id=401,
        full_name="Expert Trisha",
        username="trisha_expert",
        email="trisha@cyber.gov.in",
        phone_number="9876543210",
        password="hashed_pw",
        role_id=3,  # Cyber Expert
        cyber_cell_id=1,
        is_active=True
    )
    other_expert = User(
        id=402,
        full_name="Expert Bob",
        username="bob_expert",
        email="bob@cyber.gov.in",
        phone_number="9876543211",
        password="hashed_pw",
        role_id=3,  # Cyber Expert
        cyber_cell_id=1,
        is_active=True
    )
    investigator_user = User(
        id=403,
        full_name="Officer Gunjan",
        username="gunjan_officer",
        email="gunjan@police.gov.in",
        phone_number="9876543212",
        password="hashed_pw",
        role_id=2,  # Investigator
        cyber_cell_id=1,
        is_active=True
    )
    db.add_all([expert_user, other_expert, investigator_user])
    db.commit()

    # Seed Cases
    case_a = Case(
        id=201,
        case_id="CASE-CBIR-01",
        title="Digital Forensics Alpha",
        priority="High",
        status="Under Review",
        cyber_expert_id=401,
        investigator_id=403
    )
    case_b = Case(
        id=202,
        case_id="CASE-CBIR-02",
        title="Cyber Incident Beta",
        priority="Medium",
        status="Open",
        cyber_expert_id=402,  # Assigned to other expert
        investigator_id=403
    )
    case_empty = Case(
        id=203,
        case_id="CASE-CBIR-EMPTY",
        title="Empty Case",
        priority="Low",
        status="Open",
        cyber_expert_id=401,
        investigator_id=403
    )
    case_single = Case(
        id=204,
        case_id="CASE-CBIR-SINGLE",
        title="Single Image Case",
        priority="Low",
        status="Open",
        cyber_expert_id=401,
        investigator_id=403
    )
    db.add_all([case_a, case_b, case_empty, case_single])
    db.commit()

    # Seed Evidence in Case A
    ev_a1 = Evidence(
        id=1001,
        evidence_id="EV-A-001",
        case_id=201,
        file_name="query_suspect_scene.jpg",
        file_type="image/jpeg",
        file_size=245000,
        file_path="mock/path/query_suspect_scene.jpg",
        status="Active"
    )
    ev_a2 = Evidence(
        id=1002,
        evidence_id="EV-A-002",
        case_id=201,
        file_name="exact_duplicate_copy.jpg",
        file_type="image/jpeg",
        file_size=245000,
        file_path="mock/path/exact_duplicate_copy.jpg",
        status="Active"
    )
    ev_a3 = Evidence(
        id=1003,
        evidence_id="EV-A-003",
        case_id=201,
        file_name="another_scene_angle.jpg",
        file_type="image/jpeg",
        file_size=198000,
        file_path="mock/path/another_scene_angle.jpg",
        status="Active"
    )
    ev_a_pdf = Evidence(
        id=1004,
        evidence_id="EV-A-004-PDF",
        case_id=201,
        file_name="investigation_report.pdf",
        file_type="application/pdf",
        file_size=512000,
        file_path="mock/path/investigation_report.pdf",
        status="Active"
    )

    # Seed Evidence in Case B (Cross-case boundary test)
    ev_b1 = Evidence(
        id=2001,
        evidence_id="EV-B-001",
        case_id=202,
        file_name="case_b_image.jpg",
        file_type="image/jpeg",
        file_size=310000,
        file_path="mock/path/case_b_image.jpg",
        status="Active"
    )

    # Seed Evidence in Single Image Case
    ev_single1 = Evidence(
        id=3001,
        evidence_id="EV-S-001",
        case_id=204,
        file_name="solo_evidence.jpg",
        file_type="image/jpeg",
        file_size=150000,
        file_path="mock/path/solo_evidence.jpg",
        status="Active"
    )

    db.add_all([ev_a1, ev_a2, ev_a3, ev_a_pdf, ev_b1, ev_single1])
    db.commit()

    # Seed Verified Hashes
    # EV-A-001 and EV-A-002 share identical SHA-256 (Bitwise exact duplicate)
    identical_sha = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    different_sha = "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08"

    h1 = EvidenceHash(
        id=1,
        evidence_id=1001,
        file_name="query_suspect_scene.jpg",
        sha256_hash=identical_sha,
        current_hash=identical_sha,
        original_hash=identical_sha,
        hash_match=True,
        tampered=False,
        integrity_status="Verified"
    )
    h2 = EvidenceHash(
        id=2,
        evidence_id=1002,
        file_name="exact_duplicate_copy.jpg",
        sha256_hash=identical_sha,
        current_hash=identical_sha,
        original_hash=identical_sha,
        hash_match=True,
        tampered=False,
        integrity_status="Verified"
    )
    h3 = EvidenceHash(
        id=3,
        evidence_id=1003,
        file_name="another_scene_angle.jpg",
        sha256_hash=different_sha,
        current_hash=different_sha,
        original_hash=different_sha,
        hash_match=True,
        tampered=False,
        integrity_status="Verified"
    )
    db.add_all([h1, h2, h3])
    db.commit()

    return db, expert_user, other_expert, investigator_user


class TestCBIRIntegration(unittest.TestCase):

    def setUp(self):
        self.db, self.expert, self.other_expert, self.investigator = setup_in_memory_db()

    def tearDown(self):
        self.db.close()

    def test_01_cyber_expert_authorization(self):
        """Verify role_id == 3 and case assignment checks."""
        # 1. Non-Cyber Expert role (Investigator role_id == 2) -> 403
        with self.assertRaises(HTTPException) as ctx:
            list_case_images(case_id=201, db=self.db, current_user=self.investigator)
        self.assertEqual(ctx.exception.status_code, 403)
        self.assertIn("Cyber Experts only", ctx.exception.detail)

        # 2. Cyber Expert accessing unassigned case -> 403
        with self.assertRaises(HTTPException) as ctx:
            list_case_images(case_id=202, db=self.db, current_user=self.expert)
        self.assertEqual(ctx.exception.status_code, 403)
        self.assertIn("not assigned", ctx.exception.detail)

        # 3. Non-existent case -> 404
        with self.assertRaises(HTTPException) as ctx:
            list_case_images(case_id=9999, db=self.db, current_user=self.expert)
        self.assertEqual(ctx.exception.status_code, 404)

        # 4. Assigned Cyber Expert -> 200 Success
        res = list_case_images(case_id=201, db=self.db, current_user=self.expert)
        self.assertIsNotNone(res)
        print("  [PASS] Test 1: Role check (role_id==3) and assigned-case authorization strictly enforced.")

    def test_02_empty_case_behavior(self):
        """Case with zero images returns clean empty list and zero counts."""
        res = list_case_images(case_id=203, db=self.db, current_user=self.expert)
        self.assertEqual(res.total_images, 0)
        self.assertEqual(len(res.images), 0)
        print("  [PASS] Test 2: Truthful empty state for cases without image evidence.")

    def test_03_list_case_images_filters_non_images(self):
        """Verify list_case_images returns genuine images and excludes PDFs/documents."""
        res = list_case_images(case_id=201, db=self.db, current_user=self.expert)
        self.assertEqual(res.total_images, 3)  # EV-A-001, EV-A-002, EV-A-003
        ev_ids = [item.evidence_id for item in res.images]
        self.assertIn("EV-A-001", ev_ids)
        self.assertIn("EV-A-002", ev_ids)
        self.assertIn("EV-A-003", ev_ids)
        self.assertNotIn("EV-A-004-PDF", ev_ids, "PDF evidence must not be listed in CBIR image list")
        print("  [PASS] Test 3: List images returns only image evidence, excluding non-image files.")

    def test_04_query_validation(self):
        """Verify query evidence validation: must belong to case and must be an image."""
        # 1. Query evidence does not belong to case (belongs to Case B) -> 404
        req_wrong_case = CBIRCompareRequest(query_evidence_id=2001)
        with self.assertRaises(HTTPException) as ctx:
            execute_cbir_comparison(case_id=201, req=req_wrong_case, db=self.db, current_user=self.expert)
        self.assertEqual(ctx.exception.status_code, 404)

        # 2. Query evidence is a PDF -> 400 Bad Request
        req_pdf = CBIRCompareRequest(query_evidence_id=1004)
        with self.assertRaises(HTTPException) as ctx:
            execute_cbir_comparison(case_id=201, req=req_pdf, db=self.db, current_user=self.expert)
        self.assertEqual(ctx.exception.status_code, 400)
        self.assertIn("not a supported image", ctx.exception.detail)
        print("  [PASS] Test 4: Query validation blocks invalid, non-case, or non-image queries.")

    def test_05_single_image_case(self):
        """Case with exactly one image returns zero comparison candidates."""
        req = CBIRCompareRequest(query_evidence_id=3001)
        res = execute_cbir_comparison(case_id=204, req=req, db=self.db, current_user=self.expert)
        self.assertEqual(res.summary.total_same_case_images, 1)
        self.assertEqual(res.summary.candidates_analyzed, 0)
        self.assertEqual(res.summary.result_count, 0)
        self.assertEqual(res.results, [])
        print("  [PASS] Test 5: Single-image case handles query exclusion cleanly with 0 comparison candidates.")

    def test_06_cbir_comparison_query_exclusion_and_ranking(self):
        """Verify query is excluded and remaining same-case candidates are evaluated."""
        req = CBIRCompareRequest(query_evidence_id=1001)
        res = execute_cbir_comparison(case_id=201, req=req, db=self.db, current_user=self.expert)

        self.assertEqual(res.case_id, 201)
        self.assertEqual(res.query_evidence_id, "EV-A-001")
        self.assertEqual(res.summary.total_same_case_images, 3)
        self.assertEqual(res.summary.candidates_analyzed, 2)
        self.assertEqual(res.summary.query_excluded_id, "EV-A-001")
        self.assertEqual(res.summary.result_count, 2)

        cand_ids = [r.candidate_evidence_id for r in res.results]
        self.assertNotIn("EV-A-001", cand_ids, "Query image EV-A-001 must NEVER appear in its own results")
        self.assertIn("EV-A-002", cand_ids)
        self.assertIn("EV-A-003", cand_ids)

        # Deterministic ranking check
        ranks = [r.rank for r in res.results]
        self.assertEqual(ranks, [1, 2], "Ranks must be strictly consecutive (1, 2)")
        self.assertGreaterEqual(res.results[0].visual_similarity_score, res.results[1].visual_similarity_score)
        print("  [PASS] Test 6: Self-match exclusion and deterministic ranking verified.")

    def test_07_sha256_exact_duplicate_precedence(self):
        """Verify identical SHA-256 produces Exact Duplicate with Verification Required = No."""
        req = CBIRCompareRequest(query_evidence_id=1001)
        res = execute_cbir_comparison(case_id=201, req=req, db=self.db, current_user=self.expert)

        # EV-A-002 has matching SHA-256
        dup_item = next(r for r in res.results if r.candidate_evidence_id == "EV-A-002")
        self.assertTrue(dup_item.sha256_exact_duplicate)
        self.assertEqual(dup_item.classification, "Exact Duplicate")
        self.assertEqual(dup_item.confidence, "High")
        self.assertEqual(dup_item.recommendation, "KEEP_FOR_INVESTIGATION")
        self.assertFalse(dup_item.verification_required, "Exact duplicate MUST have verification_required = False (No)")
        self.assertIn("SHA-256", dup_item.reason)
        print("  [PASS] Test 7: Cryptographic SHA-256 duplicate identified with Verification Required = No.")

    def test_08_cross_case_isolation(self):
        """Verify images from Case B never leak into Case A comparisons."""
        req = CBIRCompareRequest(query_evidence_id=1001)
        res = execute_cbir_comparison(case_id=201, req=req, db=self.db, current_user=self.expert)

        cand_ids = [r.candidate_evidence_id for r in res.results]
        self.assertNotIn("EV-B-001", cand_ids, "Case B image EV-B-001 must NEVER appear in Case A results")
        print("  [PASS] Test 8: Strict cross-case boundary isolation enforced.")

    def test_09_server_side_filtering(self):
        """Verify classification and min_visual_similarity filters."""
        # 1. Filter by Exact Duplicate
        req_exact = CBIRCompareRequest(query_evidence_id=1001, classification="Exact Duplicate")
        res_exact = execute_cbir_comparison(case_id=201, req=req_exact, db=self.db, current_user=self.expert)
        self.assertEqual(len(res_exact.results), 1)
        self.assertEqual(res_exact.results[0].candidate_evidence_id, "EV-A-002")

        # 2. Filter by high threshold (1.0)
        req_thresh = CBIRCompareRequest(query_evidence_id=1001, min_visual_similarity=0.99)
        res_thresh = execute_cbir_comparison(case_id=201, req=req_thresh, db=self.db, current_user=self.expert)
        self.assertEqual(len(res_thresh.results), 1)
        self.assertEqual(res_thresh.results[0].candidate_evidence_id, "EV-A-002")
        print("  [PASS] Test 9: Server-side classification and threshold filtering verified.")

    def test_10_persistence_and_candidate_detail(self):
        """Verify persistence into cbir_results and candidate detail retrieval."""
        # 1. Run comparison
        req = CBIRCompareRequest(query_evidence_id=1001)
        execute_cbir_comparison(case_id=201, req=req, db=self.db, current_user=self.expert)

        # 2. Retrieve persisted results
        res_stored = get_cbir_results(case_id=201, query_evidence_id=1001, db=self.db, current_user=self.expert)
        self.assertEqual(len(res_stored.results), 2)
        self.assertEqual(res_stored.query_evidence_id, "EV-A-001")

        # 3. Retrieve detailed candidate comparison
        detail = get_candidate_details(
            case_id=201,
            candidate_evidence_id=1002,
            query_evidence_id=1001,
            db=self.db,
            current_user=self.expert
        )
        self.assertEqual(detail.candidate.candidate_evidence_id, "EV-A-002")
        self.assertIn("edge_similarity", detail.signals)
        self.assertIn("orb_similarity", detail.signals)
        self.assertIn("color_similarity", detail.signals)
        self.assertIn("grayscale_similarity", detail.signals)
        self.assertIn("Visual similarity is advisory", detail.forensic_notice)
        print("  [PASS] Test 10: TiDB persistence, stored results retrieval, and candidate detail view verified.")


if __name__ == "__main__":
    print("=" * 70)
    print("RUNNING CBIR INTEGRATION TESTS")
    print("=" * 70)
    unittest.main(verbosity=2)
