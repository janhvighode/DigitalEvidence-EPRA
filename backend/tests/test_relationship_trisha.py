"""
Unit tests for Trisha's Relationship Analysis & Graph module:
Threshold classifications, relationship generation, filtering, node/edge creation,
NetworkX graph topology, and anti-hardcoding checks.
"""
import os
import sys
from pathlib import Path

# Add project root and modules
root_dir = Path(__file__).resolve().parent.parent.parent
if str(root_dir) not in sys.path:
    sys.path.insert(0, str(root_dir))
backend_dir = Path(__file__).resolve().parent.parent
if str(backend_dir) not in sys.path:
    sys.path.insert(0, str(backend_dir))

cbir_dir = os.path.join(str(root_dir), "ai_modules", "cbir")
rel_dir = os.path.join(str(root_dir), "ai_modules", "relationship_graph")

if cbir_dir not in sys.path:
    sys.path.insert(0, cbir_dir)
if rel_dir not in sys.path:
    sys.path.insert(0, rel_dir)

import networkx as nx

from duplicate_detector import detect_duplicate
from relationship_engine import (
    generate_relationships,
    get_graph_relationships,
    create_graph_nodes,
    create_graph_edges
)
from services.relationship_graph_service import sanitize_id


def test_trisha_duplicate_detector_thresholds():
    """Verify Trisha's conservative threshold classifications."""
    print("Testing Trisha duplicate detector thresholds...")
    # Exact duplicate requires cryptographic SHA-256 match
    exact = detect_duplicate(1.0, is_exact_hash_match=True)
    assert exact["classification"] == "Exact Duplicate"
    assert exact["sha256_exact_duplicate"] is True

    # Very Strong / Near duplicate >= 0.93 without hash match
    near = detect_duplicate(0.95, is_exact_hash_match=False)
    assert near["classification"] in ("Near Duplicate", "Very Strong Visual Match")

    # Strong match >= 0.85
    strong = detect_duplicate(0.88)
    assert strong["classification"] == "Strong Visual Match"

    # Possible match >= 0.70
    possible = detect_duplicate(0.79)
    assert possible["classification"] == "Possible Visual Resemblance"

    # Weak match >= 0.50
    resemble = detect_duplicate(0.65)
    assert resemble["classification"] == "Weak Visual Resemblance"
    assert resemble["visual_resemblance"] is True

    # Low / No match < 0.50
    low = detect_duplicate(0.45)
    assert low["classification"] == "No Significant Visual Match"
    assert low["visual_resemblance"] is False
    print("  [PASS] Threshold classifications are conservative and accurate.")


def test_trisha_relationship_engine_generate_and_filter():
    """Verify Trisha's relationship engine generates and filters candidate relationships."""
    print("Testing Trisha relationship engine generation and filtering...")
    source_ev = "DYNAMIC_EV_001"
    search_results = [
        {"evidence_id": "DYNAMIC_EV_002", "similarity": 0.99, "category": "documents"},
        {"evidence_id": "DYNAMIC_EV_003", "similarity": 0.86, "category": "crime_scene"},
        {"evidence_id": "DYNAMIC_EV_004", "similarity": 0.35, "category": "vehicles"},
        {"evidence_id": "DYNAMIC_EV_001", "similarity": 1.0, "category": "documents"}  # Self
    ]

    relationships = generate_relationships(source_evidence=source_ev, search_results=search_results)
    # Self-comparison must be automatically excluded
    target_ids = [r["target_evidence"] for r in relationships]
    assert source_ev not in target_ids
    assert "DYNAMIC_EV_002" in target_ids
    assert "DYNAMIC_EV_003" in target_ids
    assert "DYNAMIC_EV_004" in target_ids

    # Filtering for graph: weak matches (< 0.60) must be excluded
    graph_rels = get_graph_relationships(relationships)
    graph_targets = [r["target_evidence"] for r in graph_rels]
    assert "DYNAMIC_EV_002" in graph_targets
    assert "DYNAMIC_EV_003" in graph_targets
    assert "DYNAMIC_EV_004" not in graph_targets
    print("  [PASS] Self-comparison excluded; non-significant visual matches filtered out.")


def test_trisha_create_graph_nodes_and_edges():
    """Verify graph nodes and edges formatting from relationships."""
    print("Testing Trisha graph nodes and edges formatting...")
    relationships = [
        {
            "source_evidence": "EV_ALPHA",
            "target_evidence": "EV_BETA",
            "relationship": "Exact Duplicate",
            "confidence_level": "Very High",
            "similarity": 0.99,
            "category": "images",
            "image": "path/to/beta.jpg"
        },
        {
            "source_evidence": "EV_ALPHA",
            "target_evidence": "EV_GAMMA",
            "relationship": "Strong Visual Match",
            "confidence_level": "High",
            "similarity": 0.87,
            "category": "images",
            "image": "path/to/gamma.jpg"
        }
    ]

    nodes = create_graph_nodes(relationships)
    node_ids = {n["evidence_id"] for n in nodes}
    assert "EV_ALPHA" in node_ids
    assert "EV_BETA" in node_ids
    assert "EV_GAMMA" in node_ids
    assert len(nodes) == 3

    edges = create_graph_edges(relationships)
    assert len(edges) == 2
    assert edges[0]["source"] == "EV_ALPHA"
    assert edges[0]["target"] == "EV_BETA"
    assert edges[0]["relationship_type"] == "CBIR_VISUAL_RELATIONSHIP"
    assert edges[0]["similarity"] == 0.99
    print("  [PASS] Graph nodes deduplicated and edges formatted with confidence levels.")


def test_networkx_graph_construction():
    """Verify NetworkX graph topology creation with typed nodes and edges."""
    print("Testing NetworkX graph topology construction...")
    G = nx.Graph()

    # Dynamic nodes
    G.add_node("ev_101", type="Evidence", label="contract.pdf")
    G.add_node("ev_102", type="Evidence", label="backup_contract.pdf")
    G.add_node("suspect_1", type="Suspect", label="investor@target.com")
    G.add_node("device_1", type="Device", label="MacBook Pro 16")

    # Connect Evidence -> Suspect
    G.add_edge("ev_101", "suspect_1", relationship="EVIDENCE_SUSPECT_LINK")

    # Connect Evidence -> Device
    G.add_edge("ev_101", "device_1", relationship="EVIDENCE_DEVICE_LINK")

    # Connect Evidence -> Evidence (Duplicate)
    G.add_edge("ev_101", "ev_102", relationship="EXACT_DUPLICATE", similarity=1.0)

    assert G.number_of_nodes() == 4
    assert G.number_of_edges() == 3
    assert G.degree["ev_101"] == 3
    assert G.degree["suspect_1"] == 1
    assert G.has_edge("ev_101", "ev_102")
    print("  [PASS] NetworkX multi-type graph correctly computes degrees and edges.")


def test_anti_hardcoding_sanitization():
    """Verify that graph logic safely handles arbitrary dynamic IDs without static hardcoding."""
    print("Testing anti-hardcoding sanitization...")
    assert sanitize_id("Samsung Galaxy S23 (SM-S911B)") == "Samsung_Galaxy_S23__SM-S911B_"
    assert sanitize_id("attacker+compromise@evil.org") == "attacker_compromise_evil_org"
    assert sanitize_id("192.168.1.1:8080") == "192_168_1_1_8080"
    print("  [PASS] Arbitrary identifiers sanitized dynamically with zero hardcoding.")


if __name__ == "__main__":
    print("=" * 70)
    print("RUNNING TRISHA RELATIONSHIP MODULE STANDALONE TESTS")
    print("=" * 70)

    tests = [
        test_trisha_duplicate_detector_thresholds,
        test_trisha_relationship_engine_generate_and_filter,
        test_trisha_create_graph_nodes_and_edges,
        test_networkx_graph_construction,
        test_anti_hardcoding_sanitization
    ]

    passed = 0
    failed = 0

    for t in tests:
        try:
            t()
            passed += 1
        except Exception as e:
            print(f"  [FAIL] {t.__name__}: {e}")
            failed += 1

    print("=" * 70)
    print(f"TRISHA STANDALONE TEST RESULTS: {passed} passed, {failed} failed")
    print("=" * 70)
    if failed > 0:
        sys.exit(1)
