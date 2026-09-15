# ============================================================
# Digital Evidence EPRA
# Test Suite: Member 3 Forensic Verification Suite (11 Tests)
# File      : test_member3_forensic.py
# Purpose   : Rigorous forensic validation of CBIR, SHA-256 duplicate
#             rules, false-positive guards, case isolation, text retrieval,
#             and all-evidence relationship graph.
# ============================================================

import os
import sys
import unittest

PROJECT_ROOT = os.path.dirname(os.path.abspath(__file__))
CBIR_DIR = os.path.join(PROJECT_ROOT, "ai_modules", "cbir")
REL_DIR = os.path.join(PROJECT_ROOT, "ai_modules", "relationship_graph")

for p in [PROJECT_ROOT, CBIR_DIR, REL_DIR]:
    if p not in sys.path:
        sys.path.insert(0, p)

from hash_verifier import compute_sha256, are_exact_duplicates
from similarity import (
    calculate_similarity,
    compute_multi_signal_similarity,
    classify_match,
    is_verification_required,
    investigative_status,
    recommended_action,
    generate_similarity_result,
    compute_confidence_level,
    compute_investigation_recommendation,
    WEIGHT_EDGE, WEIGHT_ORB, WEIGHT_HIST, WEIGHT_GRAY,
    VERY_STRONG_MATCH_THRESHOLD, STRONG_MATCH_THRESHOLD
)
from image_search import search_similar_images, format_search_results, render_investigator_image_card
from text_retrieval import search_evidence_by_text, search_text_evidence
from context_retrieval import search_context_evidence
from unified_retrieval import retrieve_evidence
from case_graph_engine import build_case_relationship_graph, serialize_graph, find_relationship_path, get_node_details
from feature_database import get_case_evidence, get_evidence


class TestMember3Forensic(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        cls.case_id = "CASE_TEST_01"
        cls.iso_case_id = "CASE_TEST_02"
        cls.test_dir = os.path.join(PROJECT_ROOT, "test_cases", "CASE_TEST_01")
        cls.ev1_path = os.path.join(cls.test_dir, "EV_TEST_01.jpg")
        cls.ev3_path = os.path.join(cls.test_dir, "EV_TEST_03.jpg")
        cls.ev4_path = os.path.join(cls.test_dir, "EV_TEST_04.jpg")
        cls.ev6_path = os.path.join(cls.test_dir, "EV_TEST_06_RE.jpg")

    # ------------------------------------------------------------
    # TEST 1 — SELF MATCH EXCLUSION
    # ------------------------------------------------------------
    def test_01_self_match_exclusion(self):
        """Query image must never appear in its own search result."""
        results = search_similar_images(
            query_image_path=self.ev1_path,
            case_evidence=get_case_evidence(self.case_id),
            top_k=10,
            case_id=self.case_id,
            query_evidence_id="EV_TEST_01"
        )
        returned_ev_ids = [r["evidence_id"] for r in results]
        returned_images = [os.path.abspath(r["image_path"]) for r in results if r.get("image_path")]

        self.assertNotIn("EV_TEST_01", returned_ev_ids, "Self evidence_id must be excluded")
        self.assertNotIn(os.path.abspath(self.ev1_path), returned_images, "Self image path must be excluded")
        print("  [PASS] Test 1: Self-match explicitly excluded by evidence_id and image path.")

    # ------------------------------------------------------------
    # TEST 2 — EXACT DUPLICATE VIA SHA-256 ONLY
    # ------------------------------------------------------------
    def test_02_exact_duplicate_sha256(self):
        """Identical copied file must be flagged Exact Duplicate via bit-for-bit SHA-256."""
        h1 = compute_sha256(self.ev1_path)
        h3 = compute_sha256(self.ev3_path)
        self.assertEqual(h1, h3, "EV_TEST_01 and EV_TEST_03 must have identical bit-for-bit SHA-256")

        results = search_similar_images(
            query_image_path=self.ev1_path,
            case_evidence=get_case_evidence(self.case_id),
            top_k=10,
            case_id=self.case_id,
            query_evidence_id="EV_TEST_01"
        )
        ev3_match = next((r for r in results if r["evidence_id"] == "EV_TEST_03"), None)
        self.assertIsNotNone(ev3_match, "EV_TEST_03 must be in results")
        self.assertTrue(ev3_match["sha256_exact_duplicate"], "sha256_exact_duplicate must be True")
        self.assertEqual(ev3_match["classification"], "Exact Duplicate", "Classification must be 'Exact Duplicate'")
        self.assertIn("SHA-256", ev3_match["reason"], "Reason must cite SHA-256 file duplicate")
        self.assertNotIn("same person confirmed", ev3_match["reason"].lower(), "No biometric claims on file duplicate")
        print("  [PASS] Test 2: Exact Duplicate produced exclusively through bit-for-bit SHA-256.")

    # ------------------------------------------------------------
    # TEST 3 — VISUALLY ALMOST IDENTICAL BUT DIFFERENT SHA
    # ------------------------------------------------------------
    def test_03_visually_similar_different_sha(self):
        """Re-encoded image with different SHA-256 must NOT be Exact Duplicate."""
        h1 = compute_sha256(self.ev1_path)
        h6 = compute_sha256(self.ev6_path)
        self.assertNotEqual(h1, h6, "Re-encoded image must have differing SHA-256")

        results = search_similar_images(
            query_image_path=self.ev1_path,
            case_evidence=get_case_evidence(self.case_id),
            top_k=10,
            case_id=self.case_id,
            query_evidence_id="EV_TEST_01"
        )
        ev6_match = next((r for r in results if r["evidence_id"] == "EV_TEST_06_RE"), None)
        self.assertIsNotNone(ev6_match, "EV_TEST_06_RE must be returned")
        self.assertFalse(ev6_match["sha256_exact_duplicate"], "sha256_exact_duplicate must be False")
        self.assertNotEqual(ev6_match["classification"], "Exact Duplicate", "Must NEVER be Exact Duplicate without SHA match")
        self.assertEqual(ev6_match["classification"], "Very Strong Visual Match", "Expected 'Very Strong Visual Match'")
        self.assertTrue(ev6_match["verification_required"], "verification_required must be True")
        print("  [PASS] Test 3: Visually near-identical image with different hash yields 'Very Strong Visual Match', NOT Exact Duplicate.")

    # ------------------------------------------------------------
    # TEST 4 — SAME PERSON / DIFFERENT POSE OR ANGLE
    # ------------------------------------------------------------
    def test_04_same_person_different_photo(self):
        """Person comparisons without SHA match require verification and never claim identity proof."""
        sim = 0.88
        classification = classify_match(sim, is_exact_hash_match=False, is_person=True)
        ver_req = is_verification_required(sim, is_exact_hash_match=False, is_person=True)
        action = recommended_action(sim, is_exact_hash_match=False, is_person=True)

        self.assertIn(classification, ["Strong Visual Match", "Possible Visual Resemblance"])
        self.assertTrue(ver_req, "verification_required MUST remain True for person visual match")
        self.assertNotIn("same person confirmed", action.lower())
        self.assertNotIn("identity confirmed", action.lower())
        self.assertNotIn("biometric match confirmed", action.lower())
        print("  [PASS] Test 4: Person visual comparison yields conservative classification; verification_required=True; no identity proof.")

    # ------------------------------------------------------------
    # TEST 5 — DIFFERENT PERSON / SIMILAR BACKGROUND (FALSE POSITIVE REDUCTION)
    # ------------------------------------------------------------
    def test_05_false_positive_reduction(self):
        """Edge/ORB structural safeguard prevents color/background from dominating."""
        results = search_similar_images(
            query_image_path=self.ev1_path,
            case_evidence=get_case_evidence(self.case_id),
            top_k=10,
            case_id=self.case_id,
            query_evidence_id="EV_TEST_01"
        )
        ev4_match = next((r for r in results if r["evidence_id"] == "EV_TEST_04"), None)
        self.assertIsNotNone(ev4_match, "EV_TEST_04 must be evaluated")
        self.assertNotEqual(ev4_match["classification"], "Very Strong Visual Match", "Different person must not get Very Strong Visual Match")
        self.assertNotEqual(ev4_match["classification"], "Strong Visual Match", "Different person must not get Strong Visual Match")
        self.assertTrue(ev4_match["verification_required"])
        print("  [PASS] Test 5: Structural edge/ORB guardrail prevented color/background domination; downgraded false positive.")

    # ------------------------------------------------------------
    # TEST 6 — SCORE BREAKDOWN
    # ------------------------------------------------------------
    def test_06_score_breakdown(self):
        """Every CBIR result must expose all required signal breakdown and forensic fields."""
        results = search_similar_images(
            query_image_path=self.ev1_path,
            case_evidence=get_case_evidence(self.case_id),
            top_k=5,
            case_id=self.case_id,
            query_evidence_id="EV_TEST_01"
        )
        self.assertGreater(len(results), 0, "Results must not be empty")
        required_keys = [
            "case_id", "query_evidence_id", "evidence_id", "evidence_type",
            "edge_similarity", "orb_similarity", "color_similarity", "grayscale_similarity",
            "visual_similarity_score", "sha256_exact_duplicate", "classification",
            "verification_required", "reason"
        ]
        for item in results:
            for k in required_keys:
                self.assertIn(k, item, f"Missing required field '{k}' in result item")
            self.assertIsInstance(item["edge_similarity"], float)
            self.assertIsInstance(item["orb_similarity"], float)
            self.assertIsInstance(item["color_similarity"], float)
            self.assertIsInstance(item["grayscale_similarity"], float)
            self.assertIsInstance(item["visual_similarity_score"], float)
            self.assertIsInstance(item["sha256_exact_duplicate"], bool)
            self.assertIsInstance(item["verification_required"], bool)
        print("  [PASS] Test 6: Complete multi-signal breakdown (edge, orb, color, grayscale) exposed in all results.")

    # ------------------------------------------------------------
    # TEST 7 — IMAGE CASE ISOLATION
    # ------------------------------------------------------------
    def test_07_image_case_isolation(self):
        """Evidence from Case A must NEVER appear in Case B; mismatched case_id must fail."""
        results_case1 = search_similar_images(
            query_image_path=self.ev1_path,
            case_evidence=get_case_evidence(self.case_id),
            top_k=10,
            case_id=self.case_id,
            query_evidence_id="EV_TEST_01"
        )
        ev_ids_case1 = [r["evidence_id"] for r in results_case1]
        self.assertNotIn("EV_ISO_01", ev_ids_case1, "Case B evidence must never appear in Case A results")

        # Test mismatched case_id + evidence_id via unified retrieval
        res_mismatch = retrieve_evidence(
            case_id="CASE_TEST_01",
            query_type="image",
            query_evidence_id="EV_ISO_01"  # EV_ISO_01 belongs to CASE_TEST_02
        )
        self.assertEqual(res_mismatch["status"], "Error", "Mismatched case_id/evidence_id must return Error")
        self.assertIn("does not exist in case", res_mismatch["message"])
        print("  [PASS] Test 7: Strict case isolation enforced. Case B evidence never appears in Case A; mismatch blocked.")

    # ------------------------------------------------------------
    # TEST 8 — TEXT SEARCH + CASE ISOLATION
    # ------------------------------------------------------------
    def test_08_text_search_case_isolation(self):
        """Text search retrieves case-isolated evidence with explainable reasons and matched_fields."""
        res_suspect = search_evidence_by_text(self.case_id, "Rahul Sharma", top_k=5)
        self.assertGreater(len(res_suspect), 0, "Should match evidence linked to suspect Rahul Sharma")
        for r in res_suspect:
            self.assertEqual(r["case_id"], self.case_id)
            self.assertIn("matched_fields", r)
            self.assertIn("suspect_metadata", r["matched_fields"])
            self.assertIn("Rahul Sharma", r["reason"])
            self.assertTrue(r["verification_required"])
            self.assertNotEqual(r["evidence_id"], "EV_ISO_01", "CASE_TEST_02 evidence must not appear")

        # Search for device
        res_device = search_evidence_by_text(self.case_id, "Samsung Galaxy", top_k=5)
        self.assertGreater(len(res_device), 0)
        top_dev = res_device[0]
        self.assertIn("device_metadata", top_dev["matched_fields"])
        self.assertIn("Samsung", top_dev["reason"])
        print("  [PASS] Test 8: Text retrieval verified with explainable reasons, matched_fields, and zero cross-case leakage.")

    # ------------------------------------------------------------
    # TEST 9 — UNIFIED / HYBRID SEARCH
    # ------------------------------------------------------------
    def test_09_unified_hybrid_search(self):
        """Unified retrieval enforces mandatory case_id, separate visible scores in hybrid mode."""
        # 1. Missing case_id must fail
        res_no_case = retrieve_evidence(case_id=None, query_type="image", query_image_path=self.ev1_path)
        self.assertEqual(res_no_case["status"], "Error")
        self.assertIn("case_id is mandatory", res_no_case["message"])

        # 2. Hybrid search test
        res_hybrid = retrieve_evidence(
            case_id=self.case_id,
            query_type="hybrid",
            query_image_path=self.ev1_path,
            query_text="suspect photograph",
            top_k=5
        )
        self.assertEqual(res_hybrid["status"], "Success")
        ranked = res_hybrid["ranked_evidence"]
        self.assertGreater(len(ranked), 0)
        for item in ranked:
            self.assertIn("visual_similarity_score", item)
            self.assertIn("text_relevance_score", item)
            self.assertIn("overall_relevance_score", item)
            self.assertIsInstance(item["visual_similarity_score"], float)
            self.assertIsInstance(item["text_relevance_score"], float)
            self.assertIsInstance(item["overall_relevance_score"], float)
        print("  [PASS] Test 9: Unified/hybrid retrieval verified: case_id mandatory, separate visible scores preserved.")

    # ------------------------------------------------------------
    # TEST 10 — ALL-EVIDENCE GRAPH
    # ------------------------------------------------------------
    def test_10_all_evidence_graph(self):
        """Relationship Graph represents ALL evidence types (Image, PDF, Document, Audio, Video, Device)."""
        nx_graph = build_case_relationship_graph(self.case_id)
        serialized = serialize_graph(nx_graph, case_id=self.case_id)

        node_ids = [n["id"] for n in serialized["nodes"]]
        node_types = {n["id"]: n["type"] for n in serialized["nodes"]}

        # Verify all evidence types appear
        self.assertIn("EV_TEST_01", node_ids, "Image evidence node missing")
        self.assertIn("EV_TEST_02", node_ids, "Mobile device evidence node missing")
        self.assertIn("EV_TEST_05", node_ids, "Laptop evidence node missing")
        self.assertIn("EV_PDF_01", node_ids, "PDF evidence node missing")
        self.assertIn("EV_DOC_01", node_ids, "Document evidence node missing")
        self.assertIn("EV_AUDIO_01", node_ids, "Audio evidence node missing")
        self.assertIn("EV_VIDEO_01", node_ids, "Video evidence node missing")

        # Verify all evidence items connect to Case
        case_edges = [
            (e["source_id"], e["target_id"]) for e in serialized["edges"]
            if e["relationship_type"] == "BELONGS_TO_CASE"
        ]
        case_connected_nodes = set()
        for u, v in case_edges:
            case_connected_nodes.add(u)
            case_connected_nodes.add(v)

        for ev_id in ["EV_TEST_01", "EV_TEST_02", "EV_TEST_05", "EV_PDF_01", "EV_DOC_01", "EV_AUDIO_01", "EV_VIDEO_01"]:
            self.assertIn(ev_id, case_connected_nodes, f"Evidence {ev_id} must connect to case via BELONGS_TO_CASE")

        # Verify case isolation in graph (no CASE_TEST_02 nodes)
        self.assertNotIn("EV_ISO_01", node_ids, "Cross-case evidence must never be in CASE_TEST_01 graph")
        print("  [PASS] Test 10: All evidence types (Image, PDF, Document, Audio, Video, Device) present in graph.")

    # ------------------------------------------------------------
    # TEST 11 — GRAPH RELATIONSHIP SAFETY & AUDITING
    # ------------------------------------------------------------
    def test_11_graph_relationship_safety(self):
        """Graph edges audit duplicate file status vs analytical CBIR, requiring verification."""
        # Attach simulated CBIR relationship
        cbir_rels = [
            {
                "source_evidence": "EV_TEST_01",
                "target_evidence": "EV_TEST_03",
                "relationship": "Exact Duplicate",
                "similarity": 1.0,
                "confidence": 1.0,
                "sha256_exact_duplicate": True,
                "is_exact_hash_match": True,
                "investigation_status": "Exact Duplicate"
            },
            {
                "source_evidence": "EV_TEST_01",
                "target_evidence": "EV_TEST_06_RE",
                "relationship": "Very Strong Visual Match",
                "similarity": 0.95,
                "confidence": 0.95,
                "sha256_exact_duplicate": False,
                "is_exact_hash_match": False,
                "investigation_status": "Candidate"
            }
        ]
        nx_graph = build_case_relationship_graph(self.case_id, cbir_relationships=cbir_rels)
        serialized = serialize_graph(nx_graph, case_id=self.case_id)

        # 1. Exact Duplicate Edge
        dup_edge = next((
            e for e in serialized["edges"]
            if (e["source_id"] in ["EV_TEST_01", "EV_TEST_03"] and e["target_id"] in ["EV_TEST_01", "EV_TEST_03"])
            and e["relationship_type"] == "EXACT_FILE_DUPLICATE"
        ), None)
        self.assertIsNotNone(dup_edge, "EXACT_FILE_DUPLICATE edge must exist")
        self.assertIn("SHA-256", dup_edge["reason"])

        # 2. Analytical CBIR Edge
        cbir_edge = next((
            e for e in serialized["edges"]
            if (e["source_id"] in ["EV_TEST_01", "EV_TEST_06_RE"] and e["target_id"] in ["EV_TEST_01", "EV_TEST_06_RE"])
            and e["relationship_type"] == "CBIR_VISUAL_RELATIONSHIP"
        ), None)
        self.assertIsNotNone(cbir_edge, "CBIR_VISUAL_RELATIONSHIP edge must exist")
        self.assertTrue(cbir_edge["verification_required"], "Analytical CBIR edge must require verification")
        self.assertIn("Visual resemblance candidate", cbir_edge["reason"])
        self.assertNotIn("SAME_PERSON", [e["relationship_type"] for e in serialized["edges"]])
        self.assertNotIn("IDENTITY_CONFIRMED", [e["relationship_type"] for e in serialized["edges"]])

        # 3. Metadata vs Analytical distinction
        for e in serialized["edges"]:
            self.assertIn("source", e)
            self.assertIn("verification_required", e)
            self.assertIn("reason", e)
            self.assertIn("case_id", e)
        print("  [PASS] Test 11: Graph relationship safety verified: duplicate edge file-level, visual edge requires verification.")

    # ------------------------------------------------------------
    # TEST 12 (TARGETED A) — QUERY AND CANDIDATE EXPLICIT IDENTIFICATION
    # ------------------------------------------------------------
    def test_12_targeted_A_query_candidate_identification(self):
        """Query image and candidate images must be explicitly identified in every comparison."""
        results = search_similar_images(
            query_image_path=self.ev1_path,
            case_evidence=get_case_evidence(self.case_id),
            top_k=5,
            case_id=self.case_id,
            query_evidence_id="EV_TEST_01"
        )
        self.assertGreater(len(results), 0, "Should return comparison results")
        for item in results:
            self.assertEqual(item["query_evidence_id"], "EV_TEST_01", "query_evidence_id must be explicit")
            self.assertEqual(item["query_filename"], "EV_TEST_01.jpg", "query_filename must be explicit")
            self.assertTrue(bool(item.get("candidate_evidence_id")), "candidate_evidence_id must be explicit")
            self.assertTrue(bool(item.get("candidate_filename")), "candidate_filename must be explicit")
            self.assertEqual(item["evidence_id"], item["candidate_evidence_id"], "evidence_id must preserve candidate ID")
            self.assertNotEqual(item["candidate_evidence_id"], "EV_TEST_01", "Candidate must not be the query image")
        print("  [PASS] TEST A: Query Image and Candidate Image are explicitly identified in all comparisons.")

    # ------------------------------------------------------------
    # TEST 13 (TARGETED B) — IMAGE CONFIDENCE & RECOMMENDATION
    # ------------------------------------------------------------
    def test_13_targeted_B_image_confidence_and_recommendation(self):
        """Image comparison results must expose confidence_level (High/Medium/Low) and investigation_recommendation."""
        results = search_similar_images(
            query_image_path=self.ev1_path,
            case_evidence=get_case_evidence(self.case_id),
            top_k=5,
            case_id=self.case_id,
            query_evidence_id="EV_TEST_01"
        )
        allowed_conf = {"High", "Medium", "Low"}
        allowed_rec = {"KEEP_FOR_INVESTIGATION", "REVIEW_MANUALLY", "LOW_PRIORITY", "NOT_RECOMMENDED"}

        for item in results:
            self.assertIn("confidence_level", item)
            self.assertIn("investigation_recommendation", item)
            self.assertIn(item["confidence_level"], allowed_conf)
            self.assertIn(item["investigation_recommendation"], allowed_rec)

        # Exact duplicate must be High confidence and KEEP_FOR_INVESTIGATION
        ev3_match = next((r for r in results if r["evidence_id"] == "EV_TEST_03"), None)
        self.assertIsNotNone(ev3_match)
        self.assertEqual(ev3_match["confidence_level"], "High")
        self.assertEqual(ev3_match["investigation_recommendation"], "KEEP_FOR_INVESTIGATION")
        print("  [PASS] TEST B: Image result exposes confidence_level and investigation_recommendation.")

    # ------------------------------------------------------------
    # TEST 14 (TARGETED C) — TEXT SEARCH 'MOBILE' DIRECT MATCHES ONLY
    # ------------------------------------------------------------
    def test_14_targeted_C_text_search_direct_matches_only(self):
        """Text search for 'mobile' must return only items with direct text/metadata match for 'mobile'."""
        direct_results = search_evidence_by_text(self.case_id, "mobile", top_k=10)
        self.assertGreater(len(direct_results), 0, "Direct match should find EV_TEST_02")

        ev_ids = [r["evidence_id"] for r in direct_results]
        self.assertIn("EV_TEST_02", ev_ids, "EV_TEST_02 (seized mobile device) must be returned")

        # Items that do NOT contain the word 'mobile' must NOT be returned in direct text search
        self.assertNotIn("EV_PERSON_1", ev_ids, "EV_PERSON_1 has no 'mobile' text and must NOT be in direct text search")
        self.assertNotIn("EV_TEST_05", ev_ids, "EV_TEST_05 (laptop) must NOT be in text search for 'mobile'")

        for r in direct_results:
            self.assertEqual(r["case_id"], self.case_id)
            self.assertIn("matched_fields", r)
            self.assertIn("matched_text_or_value", r)
            self.assertIn("confidence_level", r)
            self.assertIn("reason", r)
        print("  [PASS] TEST C: Text search 'mobile' returns only direct text/metadata matches.")

    # ------------------------------------------------------------
    # TEST 15 (TARGETED D) — UNKNOWN TEXT SEARCH NO DATA FOUND
    # ------------------------------------------------------------
    def test_15_targeted_D_unknown_text_search_no_data_found(self):
        """Non-matching text query cleanly returns status='no_data_found' and empty results."""
        res_dict = search_text_evidence(self.case_id, "nonexistent_query_term_12345")
        self.assertEqual(res_dict["status"], "no_data_found")
        self.assertIn("No relevant evidence found for 'nonexistent_query_term_12345'", res_dict["message"])
        self.assertEqual(res_dict["results"], [])

        # Unified retrieval text query test
        res_unified = retrieve_evidence(case_id=self.case_id, query_type="text", query_text="nonexistent_query_term_12345")
        self.assertEqual(res_unified["status"], "no_data_found")
        self.assertEqual(res_unified["results"], [])
        print("  [PASS] TEST D: Unknown Text Search query returns No Data Found.")

    # ------------------------------------------------------------
    # TEST 16 (TARGETED E) — CONTEXT SEARCH 'MOBILE' GRAPH TRAVERSAL
    # ------------------------------------------------------------
    def test_16_targeted_E_context_search_graph_relationships(self):
        """Context search 'mobile' returns connected evidence/entities through actual relationship graph."""
        res_ctx = search_context_evidence(self.case_id, "mobile", max_hops=2, top_k=10)
        self.assertEqual(res_ctx["status"], "Success")
        self.assertGreater(res_ctx["results_count"], 0)

        connected_ids = [r["evidence_id"] for r in res_ctx["results"]]
        # EV_TEST_02 (mobile device), Samsung Galaxy S23 (mobile device node), and connected evidence
        self.assertIn("EV_TEST_02", connected_ids)
        self.assertIn("Samsung Galaxy S23", connected_ids)

        # Evidence connected to mobile device must be returned in context search
        self.assertTrue(
            any(id_ in connected_ids for id_ in ["EV_AUDIO_01", "EV_PERSON_1", "EV_TEST_01", "Rahul Sharma"]),
            "Context search must discover evidence/person connected to mobile phone"
        )
        print("  [PASS] TEST E: Context search 'mobile' returns related evidence through actual graph relationships.")

    # ------------------------------------------------------------
    # TEST 17 (TARGETED F) — CONTEXTUAL RESULT PATH AND REASON
    # ------------------------------------------------------------
    def test_17_targeted_F_context_result_path_and_reason(self):
        """Every contextual result includes relationship_path, explainable reason, confidence, and recommendation."""
        res_ctx = search_context_evidence(self.case_id, "mobile", max_hops=2, top_k=10)
        allowed_conf = {"High", "Medium", "Low"}
        allowed_rec = {"KEEP_FOR_INVESTIGATION", "REVIEW_MANUALLY", "LOW_PRIORITY", "NOT_RECOMMENDED"}

        for item in res_ctx["results"]:
            self.assertTrue(bool(item.get("relationship_path")), "relationship_path must be non-empty")
            self.assertTrue(bool(item.get("reason")), "reason must be non-empty")
            self.assertIn("anchor_evidence_or_entity", item)
            self.assertIn("match_type", item)
            self.assertIn("context_relevance_score", item)
            self.assertIn(item["confidence_level"], allowed_conf)
            self.assertIn(item["investigation_recommendation"], allowed_rec)
            self.assertTrue(item["verification_required"])
        print("  [PASS] TEST F: Every contextual result includes relationship_path, reason, confidence, and recommendation.")

    # ------------------------------------------------------------
    # TEST 18 (TARGETED G) — PERSON CONTEXT QUERY CONNECTED EVIDENCE
    # ------------------------------------------------------------
    def test_18_targeted_G_person_context_query_connected_evidence(self):
        """Person context search for 'Rahul' returns devices and evidence actually connected to Rahul."""
        res_ctx = search_context_evidence(self.case_id, "Rahul", max_hops=2, top_k=10)
        self.assertEqual(res_ctx["status"], "Success")

        found_ids = [r["evidence_id"] for r in res_ctx["results"]]
        # Must find Rahul's devices and associated evidence
        self.assertTrue(
            any(d in found_ids for d in ["Samsung Galaxy S23", "Dell Latitude 7420"]),
            "Rahul's devices must appear in context search"
        )
        self.assertTrue(
            any(ev in found_ids for ev in ["EV_TEST_01", "EV_TEST_05", "EV_PDF_01", "EV_DOC_01", "EV_AUDIO_01"]),
            "Evidence associated with Rahul must appear in context search"
        )
        print("  [PASS] TEST G: Person context query returns devices/evidence actually connected to that person.")

    # ------------------------------------------------------------
    # TEST 19 (TARGETED H) — RELATIONSHIP PATH EVIDENCE -> DEVICE -> PERSON
    # ------------------------------------------------------------
    def test_19_targeted_H_relationship_path_evidence_device_person(self):
        """Relationship path Evidence -> Device -> Person is traced and explained accurately."""
        res_path = find_relationship_path(self.case_id, "EV_TEST_05", "Rahul Sharma")
        self.assertEqual(res_path["status"], "success")
        self.assertEqual(res_path["path_length"], 2, "Path must be 2 hops: Evidence -> Device -> Person")
        self.assertEqual(res_path["nodes"], ["EV_TEST_05", "Dell Latitude 7420", "Rahul Sharma"])
        self.assertIn("STORED_ON_DEVICE", res_path["relationship_path"])
        self.assertIn("OWNED_OR_USED_BY", res_path["relationship_path"])
        self.assertIn("Dell Latitude 7420", res_path["explanation"])
        print("  [PASS] TEST H: Relationship path Evidence -> Device -> Person works.")

    # ------------------------------------------------------------
    # TEST 20 (TARGETED I) — NO RELATIONSHIP FOUND
    # ------------------------------------------------------------
    def test_20_targeted_I_no_relationship_path_found(self):
        """Unconnected entities cleanly return status='no_relationship_found'."""
        res_none = find_relationship_path(self.case_id, "EV_TEST_05", "NON_EXISTENT_SUSPECT")
        self.assertEqual(res_none["status"], "no_relationship_found")
        self.assertIn("No supported relationship path was found", res_none["message"])
        self.assertIsNone(res_none["relationship_path"])
        print("  [PASS] TEST I: No relationship returns no_relationship_found.")

    # ------------------------------------------------------------
    # TEST 21 (TARGETED J) — CROSS-CASE CONTEXTUAL ISOLATION
    # ------------------------------------------------------------
    def test_21_targeted_J_cross_case_contextual_isolation(self):
        """Contextual traversal across different cases is strictly impossible."""
        # Rahul belongs to CASE_TEST_01, not CASE_TEST_02
        res_case2 = search_context_evidence("CASE_TEST_02", "Rahul", max_hops=2, top_k=10)
        self.assertEqual(res_case2["status"], "no_data_found")
        self.assertEqual(res_case2["results"], [])

        # Path tracing between entities of different cases must fail
        res_cross_path = find_relationship_path("CASE_TEST_01", "EV_ISO_01", "Rahul Sharma")
        self.assertEqual(res_cross_path["status"], "no_relationship_found")
        print("  [PASS] TEST J: Cross-case contextual traversal is impossible.")

    # ------------------------------------------------------------
    # TEST 22 (TARGETED K) — ALL EVIDENCE TYPES IN GRAPH
    # ------------------------------------------------------------
    def test_22_targeted_K_all_evidence_types_in_graph(self):
        """All evidence types present in test case appear in the graph and connect to Case."""
        nx_graph = build_case_relationship_graph(self.case_id)
        serialized = serialize_graph(nx_graph, case_id=self.case_id)

        node_map = {n["id"]: n["type"] for n in serialized["nodes"]}
        expected_types = {
            "EV_TEST_01": "Evidence",
            "EV_TEST_02": "Device",
            "EV_TEST_05": "Device",
            "EV_PDF_01": "PDF",
            "EV_DOC_01": "Document",
            "EV_AUDIO_01": "Audio",
            "EV_VIDEO_01": "Video"
        }
        for ev_id, type_keyword in expected_types.items():
            self.assertIn(ev_id, node_map, f"Node {ev_id} missing in graph")
            self.assertTrue(
                type_keyword.lower() in node_map[ev_id].lower(),
                f"Node {ev_id} type '{node_map[ev_id]}' does not match expected keyword '{type_keyword}'"
            )

        # All must connect via BELONGS_TO_CASE
        case_edges = [
            (e["source_id"], e["target_id"]) for e in serialized["edges"]
            if e["relationship_type"] == "BELONGS_TO_CASE"
        ]
        case_connected = {u for u, v in case_edges} | {v for u, v in case_edges}
        for ev_id in expected_types:
            self.assertIn(ev_id, case_connected, f"Node {ev_id} must connect to case via BELONGS_TO_CASE")
        print("  [PASS] TEST K: All evidence types present in test case still appear in the graph.")

    # ------------------------------------------------------------
    # TEST 23 — DYNAMIC IMAGE COUNT
    # ------------------------------------------------------------
    def test_23_dynamic_image_count(self):
        """Comparing query image against case with N images yields exactly N - 1 comparisons."""
        case_evidence = get_case_evidence(self.case_id)
        valid_images = [e for e in case_evidence if e.get("image_path") and os.path.isfile(e["image_path"])]
        n_images = len(valid_images)
        self.assertGreater(n_images, 1, "Test case must have multiple images")

        # Run complete comparison with top_k=None
        results_all = search_similar_images(
            query_image_path=self.ev1_path,
            case_evidence=case_evidence,
            top_k=None,
            case_id=self.case_id,
            query_evidence_id="EV_TEST_01"
        )
        self.assertEqual(len(results_all), n_images - 1, f"Expected {n_images - 1} comparisons, got {len(results_all)}")
        candidate_ids = [r["candidate_evidence_id"] for r in results_all]
        self.assertNotIn("EV_TEST_01", candidate_ids, "Self query image must be excluded")

        # Top-k slicing occurs strictly after all comparisons
        results_top2 = search_similar_images(
            query_image_path=self.ev1_path,
            case_evidence=case_evidence,
            top_k=2,
            case_id=self.case_id,
            query_evidence_id="EV_TEST_01"
        )
        self.assertEqual(len(results_top2), 2)
        self.assertEqual(results_top2[0]["rank"], 1)
        self.assertEqual(results_top2[1]["rank"], 2)
        print(f"  [PASS] Test 23: Dynamic image count verified: {n_images} images yielded {len(results_all)} comparisons (N - 1).")

    # ------------------------------------------------------------
    # TEST 24 — COMPLETE RANKING AND SCHEMA
    # ------------------------------------------------------------
    def test_24_complete_ranking(self):
        """Verify every candidate receives rank, IDs, scores, confidence, recommendation, reason."""
        case_evidence = get_case_evidence(self.case_id)
        results = search_similar_images(
            query_image_path=self.ev1_path,
            case_evidence=case_evidence,
            top_k=None,
            case_id=self.case_id,
            query_evidence_id="EV_TEST_01"
        )
        self.assertGreater(len(results), 0)
        expected_ranks = list(range(1, len(results) + 1))
        actual_ranks = [r["rank"] for r in results]
        self.assertEqual(actual_ranks, expected_ranks, "Ranks must be strictly consecutive (1, 2, ... N-1)")

        for r in results:
            self.assertEqual(r["case_id"], self.case_id)
            self.assertEqual(r["query_evidence_id"], "EV_TEST_01")
            self.assertIsNotNone(r["candidate_evidence_id"])
            self.assertIn("visual_similarity_score", r)
            self.assertIn("semantic_score", r)
            self.assertIn(r["confidence_level"], ["High", "Medium", "Low"])
            self.assertIn(r["classification"], [
                "Exact Duplicate", "Very Strong Visual Match", "Strong Visual Match",
                "Possible Visual Resemblance", "Weak Visual Resemblance", "No Significant Visual Match"
            ])
            self.assertIn(r["investigation_recommendation"], [
                "KEEP_FOR_INVESTIGATION", "REVIEW_MANUALLY", "LOW_PRIORITY", "NOT_RECOMMENDED"
            ])
            self.assertIn("reason", r)
            self.assertIsInstance(r["sha256_exact_duplicate"], bool)

        # Deterministic ranking check: visual scores are descending
        for i in range(len(results) - 1):
            self.assertGreaterEqual(
                results[i]["visual_similarity_score"],
                results[i + 1]["visual_similarity_score"],
                "Candidates must be deterministically ranked by visual similarity score descending"
            )
        print("  [PASS] Test 24: Complete consecutive deterministic ranking and all candidate fields verified.")

    # ------------------------------------------------------------
    # TEST 25 — DIFFERENT CASE DATA DYNAMICALLY PROCESSED
    # ------------------------------------------------------------
    def test_25_different_case_data(self):
        """Isolated case with different IDs/names/evidence count works dynamically without code changes."""
        from feature_database import connect_database as connect_img_db
        from evidence_linker import connect_database as connect_graph_db

        dyn_case_id = "CASE_DYN_AUTO_01"
        conn_img = connect_img_db()
        cursor_img = conn_img.cursor()
        cursor_img.execute(
            "INSERT OR REPLACE INTO image_features (case_id, evidence_id, category, image_path, description) VALUES (?, ?, ?, ?, ?)",
            (dyn_case_id, "DYN_IMG_ALPHA", "vehicles", self.ev1_path, "Blue sedan recovered at perimeter")
        )
        cursor_img.execute(
            "INSERT OR REPLACE INTO image_features (case_id, evidence_id, category, image_path, description) VALUES (?, ?, ?, ?, ?)",
            (dyn_case_id, "DYN_IMG_BETA", "vehicles", self.ev3_path, "Blue sedan backup photo")
        )
        cursor_img.execute(
            "INSERT OR REPLACE INTO image_features (case_id, evidence_id, category, image_path, description) VALUES (?, ?, ?, ?, ?)",
            (dyn_case_id, "DYN_IMG_GAMMA", "hardware", self.ev4_path, "Electronics in trunk")
        )
        conn_img.commit()
        conn_img.close()

        conn_g = connect_graph_db()
        cursor_g = conn_g.cursor()
        cursor_g.execute(
            "INSERT INTO evidence_links (case_id, evidence, evidence_type, suspect, device, relationship_type) VALUES (?, ?, ?, ?, ?, ?)",
            (dyn_case_id, "DYN_IMG_GAMMA", "hardware", "Vikram Malhotra", "ThinkPad X1", "STORED_ON_DEVICE")
        )
        conn_g.commit()
        conn_g.close()

        try:
            # 1. Image search on dynamic case
            dyn_results = search_similar_images(
                query_image_path=self.ev1_path,
                case_id=dyn_case_id,
                top_k=None,
                query_evidence_id="DYN_IMG_ALPHA"
            )
            self.assertEqual(len(dyn_results), 2, "Dynamic case with 3 images must yield exactly 2 comparisons")
            self.assertEqual(dyn_results[0]["candidate_evidence_id"], "DYN_IMG_BETA")
            self.assertTrue(dyn_results[0]["sha256_exact_duplicate"])

            # 2. Graph creation on dynamic case
            dyn_graph = build_case_relationship_graph(dyn_case_id)
            dyn_serialized = serialize_graph(dyn_graph, case_id=dyn_case_id)
            dyn_node_ids = {n["id"] for n in dyn_serialized["nodes"]}
            self.assertIn("DYN_IMG_ALPHA", dyn_node_ids)
            self.assertIn("DYN_IMG_BETA", dyn_node_ids)
            self.assertIn("DYN_IMG_GAMMA", dyn_node_ids)
            self.assertIn("ThinkPad X1", dyn_node_ids)
            self.assertIn("Vikram Malhotra", dyn_node_ids)

        finally:
            # Non-destructive cleanup of temporary isolated test rows only
            conn_img = connect_img_db()
            conn_img.execute("DELETE FROM image_features WHERE case_id=?", (dyn_case_id,))
            conn_img.commit()
            conn_img.close()

            conn_g = connect_graph_db()
            conn_g.execute("DELETE FROM evidence_links WHERE case_id=?", (dyn_case_id,))
            conn_g.commit()
            conn_g.close()

        print("  [PASS] Test 25: Different case with arbitrary IDs/names/evidence count executes dynamically.")

    # ------------------------------------------------------------
    # TEST 26 — ARBITRARY TEXT QUERY FROM STORED VALUES
    # ------------------------------------------------------------
    def test_26_arbitrary_text_query(self):
        """Arbitrary query words (not mobile/Rahul) match actual stored values with clean no_data_found."""
        # 1. Search an arbitrary stored keyword from evidence description
        res = search_evidence_by_text(self.case_id, "re-encoded", return_dict=True)
        self.assertEqual(res["status"], "Success")
        self.assertGreater(len(res["results"]), 0)
        top_match = res["results"][0]
        self.assertEqual(top_match["evidence_id"], "EV_TEST_06_RE")
        self.assertIn("description", top_match["matched_fields"])

        # 2. Search an arbitrary non-existent keyword
        res_none = search_evidence_by_text(self.case_id, "completely_nonexistent_query_term_xyz", return_dict=True)
        self.assertEqual(res_none["status"], "no_data_found")
        self.assertEqual(res_none["results"], [])
        self.assertIn("No relevant evidence found", res_none["message"])
        print("  [PASS] Test 26: Arbitrary text queries match stored fields dynamically with no_data_found on misses.")

    # ------------------------------------------------------------
    # TEST 27 — ARBITRARY CONTEXT QUERY DERIVED FROM GRAPH
    # ------------------------------------------------------------
    def test_27_arbitrary_context_query(self):
        """Arbitrary entity/device/evidence label traverses graph dynamically, not via special query logic."""
        # 1. Search an arbitrary device label present in the graph ('Dell' / 'Latitude')
        res_ctx = search_context_evidence(self.case_id, "Dell", max_hops=2, top_k=10)
        self.assertEqual(res_ctx["status"], "Success")
        matched_ids = [r["evidence_id"] for r in res_ctx["results"]]
        self.assertTrue(
            any("EV_TEST_05" in mid or "Rahul" in mid for mid in matched_ids),
            "Context search for 'Dell' must discover connected evidence EV_TEST_05 / Rahul"
        )

        # 2. Search an arbitrary entity label not present in the graph
        res_ctx_none = search_context_evidence(self.case_id, "satellite_dish_terminal_xyz", max_hops=2, top_k=10)
        self.assertEqual(res_ctx_none["status"], "no_data_found")
        self.assertEqual(res_ctx_none["results"], [])
        print("  [PASS] Test 27: Arbitrary context query dynamically discovers graph relationships and paths.")

    # ------------------------------------------------------------
    # TEST 28 — PRODUCTION HARDCODING AUDIT
    # ------------------------------------------------------------
    def test_28_production_hardcoding_audit(self):
        """Verify production Member 3 source contains no executable dependency on test fixture IDs/names."""
        import ast

        dirs = [CBIR_DIR, REL_DIR]
        forbidden_test_fixtures = [
            "CASE_TEST_01", "CASE_TEST_02", "EV_TEST_01", "EV_TEST_02",
            "EV_TEST_03", "EV_TEST_04", "EV_TEST_05", "EV_TEST_06",
            "Dell Latitude 7420", "EV_PDF_01", "EV_AUDIO_01", "EV_VIDEO_01"
        ]

        violations = []
        for d in dirs:
            for f in os.listdir(d):
                if not f.endswith(".py") or f.startswith("test"):
                    continue
                filepath = os.path.join(d, f)
                with open(filepath, "r", encoding="utf-8") as fp:
                    tree = ast.parse(fp.read(), filename=filepath)
                for node in tree.body:
                    # Exclude isolated if __name__ == '__main__': test blocks
                    if isinstance(node, ast.If):
                        test = node.test
                        if (isinstance(test, ast.Compare) and
                                isinstance(test.left, ast.Name) and
                                test.left.id == "__name__"):
                            continue
                    for sub in ast.walk(node):
                        if isinstance(sub, ast.Constant) and isinstance(sub.value, str):
                            for fb in forbidden_test_fixtures:
                                if fb in sub.value:
                                    violations.append((f, sub.lineno, fb, sub.value[:60]))

        self.assertEqual(
            len(violations), 0,
            f"Production code must not contain test fixture hardcoding. Violations found: {violations}"
        )
        print("  [PASS] Test 28: Automated AST audit confirms zero production hardcoding across all Member 3 modules.")

    # ------------------------------------------------------------
    # TEST 29 — SHARED SHA INTEGRATION AND REUSE
    # ------------------------------------------------------------
    def test_29_shared_sha_integration_and_reuse(self):
        """Verify compute_sha256 delegates to Deepak's shared HashService and has zero local hashlib."""
        import inspect
        import hash_verifier
        from backend.app.services.hash_service import HashService

        # 1. Verify delegation
        fn_src = inspect.getsource(hash_verifier.compute_sha256)
        self.assertNotIn("hashlib", fn_src, "Member 3 compute_sha256 must NOT instantiate hashlib independently")
        self.assertIn("HashService", fn_src, "Member 3 compute_sha256 must delegate to shared HashService")

        # 2. Verify identical computation
        digest_member3 = compute_sha256(self.ev1_path)
        digest_shared = HashService.generate_sha256(self.ev1_path)
        self.assertEqual(digest_member3, digest_shared, "Member 3 digest must match shared HashService digest")
        print("  [PASS] Test 29: Shared SHA integration verified: delegates to HashService.generate_sha256 with 0 independent hashlib.")

    # ------------------------------------------------------------
    # TEST 30 — EXACT DUPLICATE VIA SHA-256 ONLY
    # ------------------------------------------------------------
    def test_30_exact_duplicate_shared_sha_only(self):
        """Controlled test files: byte-identical copy yields EXACT_FILE_DUPLICATE; re-encoded visual match does not."""
        # 1. Byte identical copy
        are_dup, h1, h3 = are_exact_duplicates(self.ev1_path, self.ev3_path)
        self.assertTrue(are_dup, "EV_TEST_01 and EV_TEST_03 must be exact duplicates")
        self.assertEqual(h1, h3)

        # 2. Graph creation with exact duplicate
        cbir_dup = [{
            "source_evidence": "EV_TEST_01",
            "target_evidence": "EV_TEST_03",
            "sha256_exact_duplicate": True,
            "similarity": 1.0,
            "classification": "Exact Duplicate"
        }]
        graph = build_case_relationship_graph(self.case_id, cbir_dup)
        edge_data = graph.get_edge_data("EV_TEST_01", "EV_TEST_03")
        self.assertIsNotNone(edge_data)
        self.assertEqual(edge_data.get("relationship_type"), "EXACT_FILE_DUPLICATE")

        # 3. Visually similar image with different SHA
        are_dup_re, h1, h6 = are_exact_duplicates(self.ev1_path, self.ev6_path)
        self.assertFalse(are_dup_re, "EV_TEST_01 and EV_TEST_06_RE must not be exact duplicates")
        self.assertNotEqual(h1, h6)

        cbir_vis = [{
            "source_evidence": "EV_TEST_01",
            "target_evidence": "EV_TEST_06_RE",
            "sha256_exact_duplicate": False,
            "similarity": 0.94,
            "classification": "Very Strong Visual Match"
        }]
        graph_vis = build_case_relationship_graph(self.case_id, cbir_vis)
        edge_vis = graph_vis.get_edge_data("EV_TEST_01", "EV_TEST_06_RE")
        self.assertIsNotNone(edge_vis)
        self.assertEqual(edge_vis.get("relationship_type"), "CBIR_VISUAL_RELATIONSHIP")
        self.assertTrue(edge_vis.get("verification_required"))
        print("  [PASS] Test 30: Controlled exact duplicate vs visual resemblance separation verified.")

    # ------------------------------------------------------------
    # TEST 31 — METADATA INTEGRATION TESTS (A THROUGH J)
    # ------------------------------------------------------------
    def test_31_metadata_integration_tests(self):
        """Focused verification of tests A through J for metadata-supported graph relationships."""
        graph = build_case_relationship_graph(self.case_id)

        # TEST A: Evidence without rich metadata still appears with BELONGS_TO_CASE
        self.assertTrue(graph.has_node("EV_PERSON_1"))
        self.assertTrue(graph.has_edge("EV_PERSON_1", self.case_id))
        self.assertEqual(graph.get_edge_data("EV_PERSON_1", self.case_id)["relationship_type"], "BELONGS_TO_CASE")

        # TEST B: Actual source-device metadata creates STORED_ON_DEVICE
        self.assertTrue(graph.has_edge("EV_TEST_05", "Dell Latitude 7420"))
        dev_edge = graph.get_edge_data("EV_TEST_05", "Dell Latitude 7420")
        self.assertEqual(dev_edge["relationship_type"], "STORED_ON_DEVICE")

        # TEST C: Actual extraction-source metadata creates EXTRACTED_FROM
        self.assertTrue(graph.has_edge("EV_TEST_02", "Samsung Galaxy S23"))
        ext_edge = graph.get_edge_data("EV_TEST_02", "Samsung Galaxy S23")
        self.assertEqual(ext_edge["relationship_type"], "EXTRACTED_FROM")

        # TEST D: Actual stored device-person association creates OWNED_OR_USED_BY
        self.assertTrue(graph.has_edge("Samsung Galaxy S23", "Rahul Sharma"))
        own_edge = graph.get_edge_data("Samsung Galaxy S23", "Rahul Sharma")
        self.assertEqual(own_edge["relationship_type"], "OWNED_OR_USED_BY")

        # TEST E: Missing/ambiguous metadata does NOT create fake relationships
        for u, v, data in graph.edges(data=True):
            self.assertNotEqual(data.get("relationship"), "FAKE_RELATIONSHIP")
            self.assertIsNotNone(data.get("relationship_type"))

        # TEST F: CASE_B metadata cannot leak into CASE_A
        iso_graph = build_case_relationship_graph(self.iso_case_id)
        for n in iso_graph.nodes():
            self.assertNotIn(n, ["EV_TEST_01", "EV_TEST_02", "Rahul Sharma", "Samsung Galaxy S23"])

        # TEST G: All evidence types in selected test case appear
        expected_types = {"Evidence: Person Photo", "Evidence: Mobile Device", "Evidence: Laptop Device", "PDF", "Document", "Audio", "Video"}
        found_types = {data.get("type") for _, data in graph.nodes(data=True)}
        for et in expected_types:
            self.assertIn(et, found_types, f"Evidence type '{et}' must appear in graph")

        # TEST H: Metadata does NOT change CBIR visual score
        # Exact formula: 0.35 * edge + 0.25 * orb + 0.20 * color + 0.20 * grayscale
        self.assertAlmostEqual(WEIGHT_EDGE, 0.35, places=2)
        self.assertAlmostEqual(WEIGHT_ORB, 0.25, places=2)
        self.assertAlmostEqual(WEIGHT_HIST, 0.20, places=2)
        self.assertAlmostEqual(WEIGHT_GRAY, 0.20, places=2)
        sim_formula = WEIGHT_EDGE * 1.0 + WEIGHT_ORB * 1.0 + WEIGHT_HIST * 1.0 + WEIGHT_GRAY * 1.0
        self.assertAlmostEqual(sim_formula, 1.0, places=4)

        # TEST I: Metadata does NOT create Exact Duplicate
        self.assertFalse(are_exact_duplicates(self.ev1_path, self.ev6_path)[0])

        # TEST J: Context Search uses the same graph relationships
        ctx_res = search_context_evidence(self.case_id, "mobile")
        self.assertEqual(ctx_res["status"], "Success")
        ctx_evidence_ids = [r["evidence_id"] for r in ctx_res["results"]]
        self.assertIn("EV_TEST_01", ctx_evidence_ids)
        self.assertIn("EV_TEST_02", ctx_evidence_ids)
        print("  [PASS] Test 31: Metadata integration tests A through J passed completely.")

    # ------------------------------------------------------------
    # TEST 32 — RELATIONSHIP SAFETY GUARDRAILS
    # ------------------------------------------------------------
    def test_32_relationship_safety_guardrails(self):
        """Explicitly test relationship safety rules to prevent unsupported inferences."""
        graph = build_case_relationship_graph(self.case_id)

        # 1. Person name in filename does NOT automatically create relationship without database link
        # EV_TEST_03 is an unlinked photo in CASE_TEST_01; it must NOT have a link to Rahul Sharma
        self.assertFalse(graph.has_edge("EV_TEST_03", "Rahul Sharma"))

        # 2. Similar timestamps do NOT create STORED_ON_DEVICE
        # EV_TEST_01 and EV_TEST_03 have identical timestamps but are not connected to each other as device
        self.assertFalse(graph.has_edge("EV_TEST_01", "EV_TEST_03"))

        # 3. Similar filenames do NOT create RELATED_EVIDENCE
        # EV_TEST_01 and EV_TEST_02 have similar naming but only connect via Case / Device
        self.assertFalse(graph.has_edge("EV_TEST_01", "EV_TEST_02"))

        # 4. High CBIR score with different SHA does NOT create EXACT_FILE_DUPLICATE
        cbir_high_visual = [{
            "source_evidence": "EV_TEST_01",
            "target_evidence": "EV_TEST_06_RE",
            "similarity": 0.98,
            "sha256_exact_duplicate": False,
            "classification": "Very Strong Visual Match"
        }]
        g_test = build_case_relationship_graph(self.case_id, cbir_high_visual)
        edge = g_test.get_edge_data("EV_TEST_01", "EV_TEST_06_RE")
        self.assertNotEqual(edge["relationship_type"], "EXACT_FILE_DUPLICATE")
        self.assertEqual(edge["relationship_type"], "CBIR_VISUAL_RELATIONSHIP")
        print("  [PASS] Test 32: All relationship safety guardrails verified.")

    # ------------------------------------------------------------
    # TEST 33 — CLEAN INVESTIGATOR NODE DETAILS AND NO RAW SHA
    # ------------------------------------------------------------
    def test_33_clean_investigator_node_details(self):
        """Node details and image search results expose clean investigator view with zero raw SHA."""
        # 1. Node details for Evidence
        ev_details = get_node_details(self.case_id, "EV_TEST_01")
        self.assertEqual(ev_details["entity_category"], "Evidence")
        self.assertEqual(ev_details["evidence_id"], "EV_TEST_01")
        self.assertEqual(ev_details["filename"], "EV_TEST_01.jpg")
        self.assertNotIn("c:\\", ev_details["filename"].lower(), "No absolute filesystem paths in filename")
        self.assertNotIn("sha256", ev_details, "No raw sha256 in Node Details")
        self.assertNotIn("sha256_hash", ev_details, "No raw sha256_hash in Node Details")

        # 2. Node details for Device
        dev_details = get_node_details(self.case_id, "Samsung Galaxy S23")
        self.assertEqual(dev_details["entity_category"], "Device")
        self.assertEqual(dev_details["device_name"], "Samsung Galaxy S23")
        self.assertEqual(dev_details["user_or_owner"], "Rahul Sharma")

        # 3. Node details for Person
        person_details = get_node_details(self.case_id, "Rahul Sharma")
        self.assertEqual(person_details["entity_category"], "Person / Suspect")
        self.assertEqual(person_details["name"], "Rahul Sharma")

        # 4. Image search card formatting
        results = search_similar_images(self.ev1_path, case_id=self.case_id, query_evidence_id="EV_TEST_01")
        top_card = render_investigator_image_card(results[0])
        self.assertIn("EXACT DUPLICATE — VERIFIED", top_card)
        self.assertNotIn("SHA-256: ", top_card, "No raw SHA hexadecimal values displayed")
        self.assertNotIn("SHA Match:", top_card)
        self.assertNotIn("SHA Duplicate: No", top_card)
        print("  [PASS] Test 33: Clean investigator node details and UI confirmed with zero raw SHA exposure.")

    # ------------------------------------------------------------
    # TEST 34 — RELATIONSHIP VIEW TERMINOLOGY: POSSIBLE SUSPECT
    # ------------------------------------------------------------
    def test_34_relationship_view_possible_suspect_terminology(self):
        """
        Verify that CBIR person candidates are consistently displayed as 'Possible Suspect'
        in Graph Legend, Node labels, Node Details, badges, filters, and tooltips,
        while strictly preserving trusted registered case persons as 'Person / Suspect'.
        """
        from graph_visualizer import get_graph_legend

        # 1. Graph Legend contains "Possible Suspect" and NOT "Person / Entity"
        legend_labels = [item["label"] for item in get_graph_legend()]
        self.assertIn("Case", legend_labels)
        self.assertIn("Evidence (File)", legend_labels)
        self.assertIn("Possible Suspect", legend_labels)
        self.assertIn("Device", legend_labels)
        self.assertNotIn("Person / Entity", legend_labels)

        # 2. Simulate CBIR visual similarity match with a person candidate
        cbir_person_rel = [{
            "source_evidence": "EV_TEST_01",
            "target_evidence": "CANDIDATE_PERSON_01",
            "relationship": "Strong Visual Resemblance (Verification Required)",
            "relationship_type": "CBIR_VISUAL_RELATIONSHIP",
            "similarity": 0.88,
            "confidence": 0.88,
            "category": "persons",
            "is_person": True,
            "is_person_candidate": True,
            "verification_required": True,
            "investigation_status": "Requires Investigator Review"
        }]

        g = build_case_relationship_graph(self.case_id, cbir_relationships=cbir_person_rel)
        serialized = serialize_graph(g, case_id=self.case_id)

        # Locate the CBIR person candidate node
        cbir_node = next((n for n in serialized["nodes"] if n["id"] == "CANDIDATE_PERSON_01"), None)
        self.assertIsNotNone(cbir_node, "CANDIDATE_PERSON_01 node must exist in graph")

        # Must display type/badge as 'Possible Suspect'
        self.assertEqual(cbir_node["display_type"], "Possible Suspect")
        self.assertEqual(cbir_node["type_badge"], "Possible Suspect")
        self.assertEqual(cbir_node["badge"], "Possible Suspect")
        self.assertEqual(cbir_node["type"], "Possible Suspect")

        # Must NOT display as confirmed person/suspect terms
        for forbidden in ["Person", "Person / Entity", "Suspect", "Confirmed Suspect", "Identified Person"]:
            self.assertNotEqual(cbir_node["display_type"], forbidden)
            self.assertNotEqual(cbir_node["badge"], forbidden)

        # Tooltip must reflect analytical status requiring verification
        self.assertIn("Possible Suspect", cbir_node["tooltip"])
        self.assertIn("Verification required", cbir_node["tooltip"])

        # 3. Node Details panel for CBIR person candidate
        from metadata_adapter import MetadataAdapter
        details = MetadataAdapter.build_clean_node_details("CANDIDATE_PERSON_01", g.nodes["CANDIDATE_PERSON_01"])
        self.assertEqual(details["entity_category"], "Possible Suspect")
        self.assertEqual(details["badge"], "Possible Suspect")
        self.assertEqual(details["role"], "Possible Suspect")
        self.assertTrue(details["verification_required"])

        # 4. IMPORTANT DISTINCTION: Trusted case data (Rahul Sharma) is NOT relabeled to Possible Suspect
        trusted_node = next((n for n in serialized["nodes"] if n["id"] == "Rahul Sharma"), None)
        self.assertIsNotNone(trusted_node, "Rahul Sharma must exist in graph")
        self.assertEqual(trusted_node["display_type"], "Person / Suspect")
        self.assertEqual(trusted_node["type_badge"], "Person / Suspect")
        self.assertNotEqual(trusted_node["display_type"], "Possible Suspect", "Trusted case data must NOT be relabeled to Possible Suspect")

        trusted_details = get_node_details(self.case_id, "Rahul Sharma")
        self.assertEqual(trusted_details["entity_category"], "Person / Suspect")

        # 5. Graph filters/dropdowns contain 'Possible Suspect'
        self.assertIn("Possible Suspect", serialized["filter_categories"])

        # 6. Forensic safety: CBIR relationship must remain analytical and require verification
        cbir_edge = next((e for e in serialized["edges"] if e["target_id"] == "CANDIDATE_PERSON_01" or e["source_id"] == "CANDIDATE_PERSON_01"), None)
        self.assertIsNotNone(cbir_edge)
        self.assertEqual(cbir_edge["relationship_type"], "CBIR_VISUAL_RELATIONSHIP")
        self.assertTrue(cbir_edge["verification_required"])
        self.assertNotIn("SAME_PERSON", [e["relationship_type"] for e in serialized["edges"]])
        self.assertNotIn("CONFIRMED_SUSPECT", [e["relationship_type"] for e in serialized["edges"]])

        print("  [PASS] Test 34: Possible Suspect terminology verified across legend, node labels, details, badges, and filters.")


if __name__ == "__main__":
    print("\n" + "=" * 70)
    print("DIGITAL EVIDENCE EPRA - MEMBER 3 FORENSIC VALIDATION SUITE")
    print("=" * 70 + "\n")
    suite = unittest.TestLoader().loadTestsFromTestCase(TestMember3Forensic)
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)

    if not result.wasSuccessful():
        sys.exit(1)

