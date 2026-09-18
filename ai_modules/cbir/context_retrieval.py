# ============================================================
# Digital Evidence EPRA
# Module : CBIR / Context-Based Evidence Retrieval
# File   : context_retrieval.py
# Purpose: Context-based evidence retrieval using the case-isolated
#          relationship graph to find connected evidence, persons,
#          and devices through actual stored relationships.
# Author : Member 3 (Trisha)
# ============================================================

import os
import sys
import networkx as nx

CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(CURRENT_DIR, "..", ".."))
REL_GRAPH_DIR = os.path.abspath(os.path.join(PROJECT_ROOT, "ai_modules", "relationship_graph"))

for path in [PROJECT_ROOT, CURRENT_DIR, REL_GRAPH_DIR]:
    if path not in sys.path:
        sys.path.insert(0, path)

try:
    from case_graph_engine import build_case_relationship_graph
except ImportError:
    build_case_relationship_graph = None


def search_context_evidence(case_id, query_text, max_hops=2, top_k=10):
    """
    Search evidence related to the queried concept or entity through ACTUAL
    STORED RELATIONSHIPS in the case relationship graph.

    Flow:
      query
      → identify direct matching anchor evidence/person/device/entity
      → traverse SAME-CASE relationship graph (excluding trivial case root)
      → collect nearby related evidence/entities (up to max_hops)
      → rank them deterministically
      → return relationship path and forensic reasons

    Parameters
    ----------
    case_id : str
        Mandatory case identifier (strict case isolation).
    query_text : str
        Searched entity or concept (e.g. 'mobile', 'Rahul', 'Dell').
    max_hops : int, optional
        Maximum relationship hops to traverse (default: 2, max: 3).
    top_k : int, optional
        Maximum results to return.

    Returns
    -------
    dict
        Structured result with status ('Success' or 'no_data_found'), message,
        and ranked contextual evidence results.
    """
    if not case_id or not str(case_id).strip():
        return {
            "status": "error",
            "message": "case_id is mandatory for context search.",
            "case_id": None,
            "search_query": str(query_text) if query_text else "",
            "results": [],
            "ranked_evidence": [],
            "results_count": 0
        }

    case_id_str = str(case_id).strip()
    query_str = str(query_text).strip() if query_text else ""

    if not query_str:
        return {
            "status": "no_data_found",
            "message": f"No related contextual evidence found for '' in {case_id_str}.",
            "case_id": case_id_str,
            "search_query": "",
            "results": [],
            "ranked_evidence": [],
            "results_count": 0
        }

    # 1. Build case relationship graph (Single Source of Truth)
    if not build_case_relationship_graph:
        return {
            "status": "no_data_found",
            "message": f"Relationship graph engine not available.",
            "case_id": case_id_str,
            "search_query": query_str,
            "results": [],
            "ranked_evidence": [],
            "results_count": 0
        }
    graph = build_case_relationship_graph(case_id_str)
    if graph.number_of_nodes() <= 1:
        return {
            "status": "no_data_found",
            "message": f"No related contextual evidence found for '{query_str}' in {case_id_str}.",
            "case_id": case_id_str,
            "search_query": query_str,
            "results": [],
            "ranked_evidence": [],
            "results_count": 0
        }

    # Prepare search tokens
    q_lower = query_str.lower()
    q_words = [w for w in q_lower.split() if len(w) > 1]
    if not q_words:
        q_words = [q_lower]

    # 2. Identify Anchor Nodes in the graph matching query
    anchor_nodes = []
    for node_id, data in graph.nodes(data=True):
        if node_id == case_id_str:
            continue  # Do not anchor on case root

        label = str(data.get("label", node_id)).lower()
        node_type = str(data.get("type", "")).lower()
        category = str(data.get("category", "")).lower()
        desc = str(data.get("description", "")).lower()
        nid = str(node_id).lower()

        is_match = False
        match_kind = "DIRECT_TEXT_MATCH"

        if q_lower in nid or q_lower in label:
            is_match = True
            match_kind = "DIRECT_TEXT_MATCH"
        elif any(w in nid or w in label for w in q_words):
            is_match = True
            match_kind = "DIRECT_TEXT_MATCH"
        elif q_lower in desc or any(w in desc for w in q_words):
            is_match = True
            match_kind = "DIRECT_METADATA_MATCH"
        elif q_lower in category or any(w in category for w in q_words):
            is_match = True
            match_kind = "DIRECT_METADATA_MATCH"
        elif q_lower in node_type or any(w in node_type for w in q_words):
            is_match = True
            match_kind = "DIRECT_METADATA_MATCH"

        if is_match:
            anchor_nodes.append({
                "node_id": node_id,
                "label": data.get("label", str(node_id)),
                "type": data.get("type", "Entity"),
                "category": data.get("category"),
                "image_path": data.get("image_path"),
                "description": data.get("description"),
                "match_kind": match_kind
            })

    if not anchor_nodes:
        return {
            "status": "no_data_found",
            "message": f"No related contextual evidence found for '{query_str}' in {case_id_str}.",
            "case_id": case_id_str,
            "search_query": query_str,
            "results": [],
            "ranked_evidence": [],
            "results_count": 0
        }

    # 3. Create forensic traversal subgraph excluding Case root
    subgraph = graph.copy()
    if subgraph.has_node(case_id_str):
        subgraph.remove_node(case_id_str)

    max_hops_int = max(1, min(int(max_hops), 3))

    # 4. Perform multi-hop traversal from anchors
    discovered = {}  # target_id -> result_dict

    # First add anchors themselves
    for anc in anchor_nodes:
        aid = anc["node_id"]
        fn = os.path.basename(anc["image_path"]) if anc.get("image_path") else ""
        discovered[aid] = {
            "case_id": case_id_str,
            "search_query": query_str,
            "anchor_evidence_or_entity": aid,
            "evidence_id": aid,
            "entity_id": aid,
            "evidence_type": anc["type"],
            "entity_type": anc["type"],
            "filename_or_name": fn or anc["label"],
            "filename": fn,
            "image": anc.get("image_path"),
            "image_path": anc.get("image_path"),
            "match_type": anc["match_kind"],
            "hops": 0,
            "node_path": [aid],
            "relationship_path": f"{anc['label']} (Anchor)",
            "matched_field": "direct_entity_match",
            "matched_value": f"{anc['label']} ({anc['type']})",
            "snippet": f"{anc['label']} ({anc['type']})",
            "context_relevance_score": 1.0,
            "relevance_score": 1.0,
            "relevance_score_display": "100.0%",
            "semantic_score": 1.0,
            "confidence": "High",
            "confidence_level": "High",
            "investigation_recommendation": "KEEP_FOR_INVESTIGATION",
            "verification_required": True,
            "relationship_view_available": True,
            "reason": f"Directly matched search query '{query_str}' in actual stored {anc['type']} metadata."
        }

    # BFS from each anchor
    for anc in anchor_nodes:
        aid = anc["node_id"]
        if not subgraph.has_node(aid):
            continue

        lengths = nx.single_source_shortest_path_length(subgraph, aid, cutoff=max_hops_int)
        paths = nx.single_source_shortest_path(subgraph, aid, cutoff=max_hops_int)

        for target_id, hop_count in lengths.items():
            if target_id == aid or hop_count == 0:
                continue

            node_path = paths[target_id]
            t_data = subgraph.nodes[target_id]
            t_type = t_data.get("type", "Entity")
            t_label = t_data.get("label", str(target_id))
            img_p = t_data.get("image_path")
            fn = os.path.basename(img_p) if img_p else ""
            fn_or_name = fn or t_label

            # Determine match_type based on intermediate entities
            match_type = "RELATED_THROUGH_EVIDENCE"
            types_in_path = [str(subgraph.nodes[n].get("type", "")).lower() for n in node_path]
            if any("device" in tp or "phone" in tp or "laptop" in tp for tp in types_in_path):
                match_type = "RELATED_THROUGH_DEVICE"
            elif any("person" in tp or "suspect" in tp for tp in types_in_path):
                match_type = "RELATED_THROUGH_PERSON"
            elif any("suspect" in tp for tp in types_in_path):
                match_type = "RELATED_THROUGH_SUSPECT"

            # Build explainable relationship path string with relationship types
            path_steps = []
            for i in range(len(node_path) - 1):
                u = node_path[i]
                v = node_path[i + 1]
                edge_data = subgraph.get_edge_data(u, v) or {}
                rel_type = edge_data.get("relationship_type", edge_data.get("relationship", "ASSOCIATED_WITH"))
                u_lbl = subgraph.nodes[u].get("label", u)
                v_lbl = subgraph.nodes[v].get("label", v)
                if i == 0:
                    path_steps.append(f"{u_lbl} -> {rel_type} -> {v_lbl}")
                else:
                    path_steps.append(f"{rel_type} -> {v_lbl}")

            rel_path_str = " -> ".join(path_steps)

            # Calculate context score based on distance
            if hop_count == 1:
                rel_score = 0.85
                conf_level = "High"
                inv_rec = "KEEP_FOR_INVESTIGATION"
            elif hop_count == 2:
                rel_score = 0.65
                conf_level = "Medium"
                inv_rec = "REVIEW_MANUALLY"
            else:
                rel_score = 0.45
                conf_level = "Low"
                inv_rec = "LOW_PRIORITY"

            reason = (
                f"{t_label} is related because backend metadata records it as connected "
                f"to {anc['label']} via: {rel_path_str}."
            )

            # Keep shortest/strongest relationship if already discovered
            if target_id in discovered:
                if discovered[target_id]["context_relevance_score"] < rel_score:
                    discovered[target_id].update({
                        "anchor_evidence_or_entity": aid,
                        "match_type": match_type,
                        "hops": hop_count,
                        "node_path": node_path,
                        "relationship_path": rel_path_str,
                        "matched_field": f"context: {match_type.lower()}",
                        "matched_value": rel_path_str,
                        "snippet": rel_path_str,
                        "context_relevance_score": rel_score,
                        "relevance_score": rel_score,
                        "relevance_score_display": f"{rel_score * 100:.1f}%",
                        "semantic_score": round(rel_score, 2),
                        "confidence": conf_level,
                        "confidence_level": conf_level,
                        "investigation_recommendation": inv_rec,
                        "relationship_view_available": True,
                        "reason": reason
                    })
            else:
                discovered[target_id] = {
                    "case_id": case_id_str,
                    "search_query": query_str,
                    "anchor_evidence_or_entity": aid,
                    "evidence_id": str(target_id),
                    "entity_id": str(target_id),
                    "evidence_type": t_type,
                    "entity_type": t_type,
                    "filename_or_name": fn_or_name,
                    "filename": fn,
                    "image": img_p,
                    "image_path": img_p,
                    "match_type": match_type,
                    "hops": hop_count,
                    "node_path": node_path,
                    "relationship_path": rel_path_str,
                    "matched_field": f"context: {match_type.lower()}",
                    "matched_value": rel_path_str,
                    "snippet": rel_path_str,
                    "context_relevance_score": rel_score,
                    "relevance_score": rel_score,
                    "relevance_score_display": f"{rel_score * 100:.1f}%",
                    "semantic_score": round(rel_score, 2),
                    "confidence": conf_level,
                    "confidence_level": conf_level,
                    "investigation_recommendation": inv_rec,
                    "verification_required": True,
                    "relationship_view_available": True,
                    "reason": reason
                }

    ranked_results = list(discovered.values())

    # Deterministic ranking: score descending, then hops ascending, then evidence_id ascending
    ranked_results.sort(key=lambda x: (-x["context_relevance_score"], x["hops"], str(x["evidence_id"])))

    try:
        limit = int(top_k)
    except (TypeError, ValueError):
        limit = 10
    limit = max(1, limit)

    ranked_results = ranked_results[:limit]
    for rank, item in enumerate(ranked_results, start=1):
        item["rank"] = rank

    if not ranked_results:
        return {
            "status": "no_data_found",
            "message": f"No related contextual evidence found for '{query_str}' in {case_id_str}.",
            "case_id": case_id_str,
            "search_query": query_str,
            "results": [],
            "ranked_evidence": [],
            "results_count": 0
        }

    return {
        "status": "Success",
        "message": f"Found {len(ranked_results)} contextual evidence item(s) related to '{query_str}' in {case_id_str}.",
        "case_id": case_id_str,
        "search_query": query_str,
        "results": ranked_results,
        "ranked_evidence": ranked_results,
        "results_count": len(ranked_results)
    }


def search_evidence_by_context(case_id, query_text, max_hops=2, top_k=10):
    """
    Alias for search_context_evidence.
    """
    return search_context_evidence(case_id, query_text, max_hops=max_hops, top_k=top_k)


def format_investigator_context_result(item):
    """
    Format a contextual search match into a clean investigator-facing card dictionary.
    Exposes: Rank, Evidence/Entity ID, Type, Filename/Name, Match Type,
    Relationship Path, Context Relevance Score (%), Semantic Score (%),
    Confidence, Investigation Recommendation, Reason.
    """
    if not isinstance(item, dict):
        return {}

    rank = item.get("rank", 1)
    ctx_rel = float(item.get("context_relevance_score", 0.0))
    sem_score = float(item.get("semantic_score", ctx_rel))

    # Format easy-to-read arrow path
    rel_path = item.get("relationship_path", "")
    readable_arrow_path = rel_path.replace(" -> ", "\n  -> ")

    return {
        "rank": rank,
        "rank_display": f"RANK #{rank}",
        "evidence_or_entity_id": item.get("evidence_id", item.get("entity_id", "")),
        "type": item.get("evidence_type", item.get("entity_type", "Entity")),
        "filename_or_name": item.get("filename_or_name", item.get("filename", "")),
        "match_type": item.get("match_type", "DIRECT_MATCH"),
        "relationship_path": rel_path,
        "relationship_path_display": readable_arrow_path,
        "context_relevance_score": f"{ctx_rel * 100:.2f}%",
        "semantic_score": f"{sem_score * 100:.0f}%" if (sem_score * 100) % 1 == 0 else f"{sem_score * 100:.2f}%",
        "confidence_level": item.get("confidence_level", "Medium"),
        "investigation_recommendation": item.get("investigation_recommendation", "REVIEW_MANUALLY"),
        "reason": item.get("reason", "")
    }


def render_investigator_context_card(item):
    """
    Render a clean, human-readable terminal/UI card for context search results.
    """
    data = format_investigator_context_result(item)
    if not data:
        return ""

    lines = [
        "-" * 42,
        data["rank_display"],
        "-" * 42,
        f"Evidence / Entity ID : {data['evidence_or_entity_id']}",
        f"Type                 : {data['type']}",
        f"Filename / Name      : {data['filename_or_name']}",
        f"Match Type           : {data['match_type']}",
        f"Relationship Path    :\n  {data['relationship_path_display']}",
        f"Context Relevance    : {data['context_relevance_score']}",
        f"Semantic Score       : {data['semantic_score']}",
        f"Confidence           : {data['confidence_level']}",
        f"Recommendation       : {data['investigation_recommendation']}",
        f"Reason               : {data['reason']}"
    ]
    return "\n".join(lines)


def render_investigator_context_results(results):
    """
    Render complete list of context search results.
    """
    if not results:
        return "No related contextual evidence found."
    return "\n\n".join(render_investigator_context_card(r) for r in results)

