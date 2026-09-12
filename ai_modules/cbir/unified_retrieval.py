# ============================================================
# Digital Evidence EPRA
# Module : CBIR / Unified Evidence Retrieval
# File   : unified_retrieval.py
# Purpose: Unified, case-isolated forensic retrieval layer for
#          image (CBIR), text/context, and hybrid queries with
#          structured forensic report generation.
# Author : Member 3 (Trisha)
# ============================================================

import os
import sys
from datetime import datetime, timezone

CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(CURRENT_DIR, "..", ".."))
REL_GRAPH_DIR = os.path.abspath(os.path.join(PROJECT_ROOT, "ai_modules", "relationship_graph"))

for path in [PROJECT_ROOT, CURRENT_DIR, REL_GRAPH_DIR]:
    if path not in sys.path:
        sys.path.insert(0, path)

from feature_database import get_case_evidence, get_evidence
from image_search import search_similar_images, format_search_results
from text_retrieval import search_evidence_by_text
from context_retrieval import search_context_evidence
from case_graph_engine import build_case_relationship_graph, serialize_graph, find_relationship_path
from relationship_engine import generate_relationships


FORENSIC_DISCLAIMER = (
    "FORENSIC NOTICE (ISO/IEC 27037 & Judicial Admissibility Standards): "
    "CBIR visual similarity scores and contextual text rankings are investigative "
    "analytical aids only. They do NOT by themselves establish person identity, "
    "ownership, authenticity, or criminal culpability. Exact duplicate status "
    "requires bit-for-bit cryptographic SHA-256 hash equality. All visual matches "
    "require independent forensic verification by an authorized investigator."
)


def retrieve_evidence(
    case_id,
    query_type="image",
    query_image_path=None,
    query_evidence_id=None,
    query_text=None,
    top_k=5,
    include_graph=True
):
    """
    Unified forensic retrieval entry point for an investigation case.

    Parameters
    ----------
    case_id : str
        Mandatory case identifier (strict case isolation).
    query_type : str, optional
        'image', 'text', or 'hybrid' (default: 'image').
    query_image_path : str, optional
        File path of the query image (for image or hybrid query).
    query_evidence_id : str, optional
        Evidence ID of the query item if querying from case evidence.
    query_text : str, optional
        Contextual query string (for text or hybrid query).
    top_k : int, optional
        Maximum number of ranked results to return (default: 5).
    include_graph : bool, optional
        Whether to generate and attach the case relationship graph (default: True).

    Returns
    -------
    dict
        Structured forensic report with ranked evidence, score breakdowns,
        audit trails, and relationship graph.
    """
    timestamp = datetime.now(timezone.utc).isoformat()

    # --------------------------------------------------------
    # 1. Validate Case ID (Mandatory Case Isolation)
    # --------------------------------------------------------
    if not case_id or not str(case_id).strip():
        return {
            "status": "Error",
            "message": "case_id is mandatory. Cross-case queries are strictly prohibited.",
            "case_id": None,
            "query_type": query_type,
            "timestamp": timestamp,
            "ranked_evidence": [],
            "forensic_notice": FORENSIC_DISCLAIMER
        }

    case_id_str = str(case_id).strip()

    try:
        top_k = max(1, min(int(top_k), 50))
    except (TypeError, ValueError):
        top_k = 5

    # Fetch all evidence belonging strictly to this case
    case_evidence = get_case_evidence(case_id_str)
    if not case_evidence:
        return {
            "status": "No Evidence",
            "message": f"No evidence registered under case '{case_id_str}'.",
            "case_id": case_id_str,
            "query_type": query_type,
            "timestamp": timestamp,
            "ranked_evidence": [],
            "relationships": [],
            "graph": {"nodes": [], "edges": [], "total_nodes": 0, "total_edges": 0},
            "forensic_notice": FORENSIC_DISCLAIMER
        }

    # --------------------------------------------------------
    # 2. Resolve Query Evidence if query_evidence_id is supplied
    # --------------------------------------------------------
    if query_evidence_id and not query_image_path:
        ev_item = get_evidence(case_id_str, str(query_evidence_id))
        if not ev_item:
            return {
                "status": "Error",
                "message": f"Evidence '{query_evidence_id}' does not exist in case '{case_id_str}'.",
                "case_id": case_id_str,
                "query_evidence_id": query_evidence_id,
                "query_type": query_type,
                "timestamp": timestamp,
                "ranked_evidence": [],
                "forensic_notice": FORENSIC_DISCLAIMER
            }
        query_image_path = ev_item.get("image_path")

    # --------------------------------------------------------
    # 3. Execute Query Based on query_type
    # --------------------------------------------------------
    ranked_evidence = []
    cbir_relationships = []

    if query_type == "image":
        if not query_image_path or not os.path.isfile(query_image_path):
            return {
                "status": "Error",
                "message": "Valid query_image_path or query_evidence_id is required for image query.",
                "case_id": case_id_str,
                "query_type": query_type,
                "timestamp": timestamp,
                "ranked_evidence": [],
                "forensic_notice": FORENSIC_DISCLAIMER
            }

        raw_results = search_similar_images(
            query_image_path=query_image_path,
            case_evidence=case_evidence,
            top_k=top_k,
            case_id=case_id_str,
            query_evidence_id=query_evidence_id
        )
        ranked_evidence = format_search_results(raw_results)

        # Generate CBIR relationships for the graph
        if query_evidence_id:
            cbir_relationships = generate_relationships(
                source_evidence=str(query_evidence_id),
                search_results=ranked_evidence
            )

    elif query_type == "text":
        if not query_text or not str(query_text).strip():
            return {
                "status": "Error",
                "message": "query_text is required for text query.",
                "case_id": case_id_str,
                "query_type": query_type,
                "timestamp": timestamp,
                "results": [],
                "ranked_evidence": [],
                "forensic_notice": FORENSIC_DISCLAIMER
            }

        ranked_evidence = search_evidence_by_text(
            case_id=case_id_str,
            query_text=str(query_text).strip(),
            top_k=top_k
        )

        if not ranked_evidence:
            return {
                "status": "no_data_found",
                "message": f"No relevant evidence found for '{query_text}' in {case_id_str}.",
                "case_id": case_id_str,
                "query_type": "text",
                "query": str(query_text).strip(),
                "search_query": str(query_text).strip(),
                "timestamp": timestamp,
                "results": [],
                "ranked_evidence": [],
                "results_count": 0,
                "verified_duplicates": [],
                "relationships": [],
                "graph": {"nodes": [], "edges": [], "total_nodes": 0, "total_edges": 0},
                "forensic_notice": FORENSIC_DISCLAIMER
            }

    elif query_type == "context":
        if not query_text or not str(query_text).strip():
            return {
                "status": "Error",
                "message": "query_text is required for context query.",
                "case_id": case_id_str,
                "query_type": query_type,
                "timestamp": timestamp,
                "results": [],
                "ranked_evidence": [],
                "forensic_notice": FORENSIC_DISCLAIMER
            }

        ctx_res = search_context_evidence(
            case_id=case_id_str,
            query_text=str(query_text).strip(),
            top_k=top_k
        )

        if ctx_res.get("status") == "no_data_found" or not ctx_res.get("results"):
            return {
                "status": "no_data_found",
                "message": ctx_res.get("message", f"No related contextual evidence found for '{query_text}' in {case_id_str}."),
                "case_id": case_id_str,
                "query_type": "context",
                "query": str(query_text).strip(),
                "search_query": str(query_text).strip(),
                "timestamp": timestamp,
                "results": [],
                "ranked_evidence": [],
                "results_count": 0,
                "verified_duplicates": [],
                "relationships": [],
                "graph": {"nodes": [], "edges": [], "total_nodes": 0, "total_edges": 0},
                "forensic_notice": FORENSIC_DISCLAIMER
            }

        ranked_evidence = ctx_res.get("results", [])

    elif query_type == "hybrid":
        # Combine image visual search + contextual text search
        img_results = []
        if query_image_path and os.path.isfile(query_image_path):
            raw_img = search_similar_images(
                query_image_path=query_image_path,
                case_evidence=case_evidence,
                top_k=len(case_evidence),
                case_id=case_id_str,
                query_evidence_id=query_evidence_id
            )
            img_results = format_search_results(raw_img)

        txt_results = []
        if query_text and str(query_text).strip():
            txt_results = search_evidence_by_text(
                case_id=case_id_str,
                query_text=str(query_text).strip(),
                top_k=len(case_evidence)
            )

        # Index text results by evidence_id
        txt_map = {r["evidence_id"]: r for r in txt_results}
        img_map = {r["evidence_id"]: r for r in img_results}

        all_ev_ids = list(dict.fromkeys(list(img_map.keys()) + list(txt_map.keys())))
        combined_list = []

        for ev_id in all_ev_ids:
            ir = img_map.get(ev_id)
            tr = txt_map.get(ev_id)

            v_score = ir["visual_similarity_score"] if ir else 0.0
            t_score = tr["text_relevance_score"] if tr else 0.0

            # Transparent heuristic combination (never hide individual scores)
            overall = round(0.60 * v_score + 0.40 * t_score, 4)

            base = ir if ir else tr
            combined_item = dict(base)
            combined_item["visual_similarity_score"] = float(v_score)
            combined_item["text_relevance_score"] = float(t_score)
            combined_item["overall_relevance_score"] = float(overall)

            if ir and ir.get("sha256_exact_duplicate"):
                combined_item["classification"] = "Exact Duplicate"
                combined_item["investigation_status"] = "Exact Duplicate"
                combined_item["sha256_exact_duplicate"] = True
                combined_item["verification_required"] = False
                combined_item["reason"] = "SHA-256 hashes are identical; files are exact bit-for-bit duplicates."
            elif overall >= 0.85:
                combined_item["classification"] = "Strong Visual / Context Match"
                combined_item["investigation_status"] = "Candidate"
                combined_item["verification_required"] = True
            elif overall >= 0.70:
                combined_item["classification"] = "Possible Resemblance"
                combined_item["investigation_status"] = "Possible Relationship"
                combined_item["verification_required"] = True
            elif overall >= 0.50:
                combined_item["classification"] = "Weak Resemblance"
                combined_item["investigation_status"] = "Requires Verification"
                combined_item["verification_required"] = True
            else:
                combined_item["classification"] = "No Significant Match"
                combined_item["investigation_status"] = "No Significant Match"
                combined_item["verification_required"] = True

            combined_list.append(combined_item)

        # Deterministic sorting
        combined_list.sort(key=lambda x: (-x["overall_relevance_score"], str(x["evidence_id"])))
        for rank, item in enumerate(combined_list[:top_k], start=1):
            item["rank"] = rank
        ranked_evidence = combined_list[:top_k]

        if query_evidence_id:
            cbir_relationships = generate_relationships(
                source_evidence=str(query_evidence_id),
                search_results=ranked_evidence
            )

    else:
        return {
            "status": "Error",
            "message": f"Unsupported query_type '{query_type}'. Use 'image', 'text', 'context', or 'hybrid'.",
            "case_id": case_id_str,
            "query_type": query_type,
            "timestamp": timestamp,
            "results": [],
            "ranked_evidence": [],
            "forensic_notice": FORENSIC_DISCLAIMER
        }

    # --------------------------------------------------------
    # 4. Separate Exact Cryptographic Duplicates
    # --------------------------------------------------------
    verified_duplicates = [
        item for item in ranked_evidence
        if item.get("sha256_exact_duplicate") is True
    ]

    # --------------------------------------------------------
    # 5. Build Case Relationship Graph if Requested
    # --------------------------------------------------------
    serialized_graph = {"nodes": [], "edges": [], "total_nodes": 0, "total_edges": 0}
    if include_graph:
        nx_graph = build_case_relationship_graph(
            case_id=case_id_str,
            cbir_relationships=cbir_relationships
        )
        serialized_graph = serialize_graph(nx_graph, case_id=case_id_str)

    query_fn = os.path.basename(query_image_path) if query_image_path else ""

    # --------------------------------------------------------
    # 6. Construct Final Structured Forensic Report
    # --------------------------------------------------------
    return {
        "status": "Success",
        "case_id": case_id_str,
        "query_type": query_type,
        "query": query_text if query_type in ["text", "context"] else query_image_path,
        "search_query": query_text if query_type in ["text", "context"] else query_fn,
        "query_evidence_id": query_evidence_id,
        "query_filename": query_fn,
        "total_case_evidence": len(case_evidence),
        "results_count": len(ranked_evidence),
        "results": ranked_evidence,
        "ranked_evidence": ranked_evidence,
        "verified_duplicates": verified_duplicates,
        "relationships": cbir_relationships,
        "graph": serialized_graph,
        "timestamp": timestamp,
        "forensic_notice": FORENSIC_DISCLAIMER
    }


if __name__ == "__main__":
    print("=" * 70)
    print("DIGITAL EVIDENCE EPRA - UNIFIED RETRIEVAL ENGINE")
    print("=" * 70)

    # Test text retrieval under CASE_DEFAULT
    res_text = retrieve_evidence(
        case_id="CASE_DEFAULT",
        query_type="text",
        query_text="mobile phone",
        top_k=3
    )
    print(f"\nText Query Status: {res_text['status']}")
    print(f"Results: {res_text['results_count']}")
    for item in res_text["ranked_evidence"]:
        print(f"  Rank {item['rank']}: {item['evidence_id']} [{item['classification']}] - Score: {item['overall_relevance_score']}")

    print("\n" + "=" * 70)
