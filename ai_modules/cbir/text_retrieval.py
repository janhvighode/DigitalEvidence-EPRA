# ============================================================
# Digital Evidence EPRA
# Module : CBIR / Forensic Retrieval
# File   : text_retrieval.py
# Purpose: Text and context-based evidence retrieval within a
#          selected investigation case.
# ============================================================

import os
import sys
import re
import sqlite3

CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(CURRENT_DIR, "..", ".."))
REL_GRAPH_DIR = os.path.abspath(os.path.join(PROJECT_ROOT, "ai_modules", "relationship_graph"))

for path in [PROJECT_ROOT, CURRENT_DIR, REL_GRAPH_DIR]:
    if path not in sys.path:
        sys.path.insert(0, path)

from feature_database import get_case_evidence, connect_database
from evidence_linker import get_case_links


STOP_WORDS = {
    "a", "an", "the", "and", "or", "in", "on", "at", "by", "for",
    "with", "about", "to", "from", "of", "is", "was", "are", "were",
    "this", "that", "these", "those", "it", "its", "related", "connected"
}

CATEGORY_SYNONYMS = {
    "car": ["car", "vehicle", "automobile", "cars", "vehicles"],
    "vehicle": ["car", "vehicle", "automobile", "cars", "vehicles"],
    "mobile": ["mobile", "phone", "smartphone", "cellphone", "mobiles", "phones", "device"],
    "phone": ["mobile", "phone", "smartphone", "cellphone", "mobiles", "phones", "device"],
    "laptop": ["laptop", "computer", "notebook", "pc", "laptops", "device"],
    "computer": ["laptop", "computer", "pc", "laptops", "desktop", "device"],
    "document": ["document", "pdf", "invoice", "receipt", "paper", "documents", "invoce"],
    "invoice": ["document", "invoice", "invoce", "bill", "receipt"],
    "gun": ["gun", "weapon", "firearm", "pistol", "rifle", "weapons", "guns"],
    "weapon": ["gun", "weapon", "firearm", "knife", "weapons"],
    "person": ["person", "suspect", "individual", "human", "persons", "people", "man", "woman"],
    "suspect": ["suspect", "person", "accused", "perpetrator", "individual"],
    "scene": ["scene", "crime_scene", "location", "site"]
}


def tokenize(text):
    """
    Extract lowercase alphanumeric tokens, filtering stop words.
    """
    if not text:
        return []
    words = re.findall(r"\b[a-zA-Z0-9_]+\b", str(text).lower())
    return [w for w in words if w not in STOP_WORDS and len(w) > 1]


def expand_query_tokens(tokens):
    """
    Expand query tokens with known forensic category synonyms.
    """
    expanded = set(tokens)
    for token in tokens:
        if token in CATEGORY_SYNONYMS:
            expanded.update(CATEGORY_SYNONYMS[token])
    return list(expanded)


def build_evidence_context(case_id, evidence_item, case_links_map=None):
    """
    Construct a consolidated searchable text context for an evidence item.
    Combines: evidence_id, category, description, filename, associated suspect,
    associated device, and relationship types.
    """
    ev_id = str(evidence_item.get("evidence_id", ""))
    cat = str(evidence_item.get("category", "")).lower()
    desc = str(evidence_item.get("description", "") or "").lower()
    img_path = str(evidence_item.get("image_path", "")).lower()
    img_basename = os.path.splitext(os.path.basename(img_path))[0] if img_path else ""

    suspect_name = ""
    device_name = ""
    rel_type = ""

    if case_links_map and ev_id in case_links_map:
        link_data = case_links_map[ev_id]
        suspect_name = str(link_data.get("suspect", "")).lower()
        device_name = str(link_data.get("device", "")).lower()
        rel_type = str(link_data.get("relationship_type", "")).lower()

    full_context = f"{ev_id} {cat} {desc} {img_basename} {suspect_name} {device_name} {rel_type}".strip()

    return {
        "full_text": full_context,
        "tokens": set(tokenize(full_context)),
        "category": cat,
        "suspect": suspect_name,
        "device": device_name,
        "relationship_type": rel_type
    }


def search_evidence_by_text(case_id, query_text, top_k=10, return_dict=False):
    """
    Search and rank evidence in a selected case matching the query text directly.
    Searches actual stored searchable fields (evidence_id, category, description,
    filename, suspect metadata, device metadata) without fabricating data.

    Parameters
    ----------
    case_id : str
        The case ID to search within (strict case isolation).
    query_text : str
        Direct textual query string.
    top_k : int, optional
        Maximum number of results to return.
    return_dict : bool, optional
        If True, return structured dict with status ('Success' or 'no_data_found').
        If False, return list of result items for backward compatibility.

    Returns
    -------
    list of dict or dict
        Ranked evidence results with relevance scores, matched fields, and forensic audit fields.
    """
    if not case_id or not query_text or not str(query_text).strip():
        if return_dict:
            return {
                "status": "no_data_found",
                "message": f"No relevant evidence found for '{query_text}' in {case_id}.",
                "case_id": str(case_id) if case_id else None,
                "search_query": str(query_text) if query_text else "",
                "results": [],
                "ranked_evidence": [],
                "results_count": 0
            }
        return []

    case_id_str = str(case_id).strip()
    query_str = str(query_text).strip()

    # 1. Fetch case-isolated evidence from feature database
    case_evidence = list(get_case_evidence(case_id_str))
    existing_ev_ids = {str(ev.get("evidence_id")) for ev in case_evidence if ev.get("evidence_id")}

    # 2. Fetch case links (suspects, devices, other evidence types like PDF/video/audio)
    links = get_case_links(case_id_str)
    links_map = {}
    for l in links:
        ev_key = str(l.get("evidence", ""))
        links_map[ev_key] = l
        if ev_key and ev_key not in existing_ev_ids:
            case_evidence.append({
                "evidence_id": ev_key,
                "category": l.get("evidence_type", "Document"),
                "description": f"{l.get('evidence_type', 'Evidence')} evidence associated with case {case_id_str}",
                "image_path": None,
                "case_id": case_id_str
            })
            existing_ev_ids.add(ev_key)

    if not case_evidence:
        if return_dict:
            return {
                "status": "no_data_found",
                "message": f"No relevant evidence found for '{query_str}' in {case_id_str}.",
                "case_id": case_id_str,
                "search_query": query_str,
                "results": [],
                "ranked_evidence": [],
                "results_count": 0
            }
        return []

    # 3. Process query tokens (lowercase)
    raw_query_tokens = tokenize(query_str)
    query_lower = query_str.lower()
    if not raw_query_tokens and len(query_lower) < 2:
        if return_dict:
            return {
                "status": "no_data_found",
                "message": f"No relevant evidence found for '{query_str}' in {case_id_str}.",
                "case_id": case_id_str,
                "search_query": query_str,
                "results": [],
                "ranked_evidence": [],
                "results_count": 0
            }
        return []

    # If tokenize removed short tokens, fall back to simple word splitting
    if not raw_query_tokens:
        raw_query_tokens = [w for w in re.findall(r"\b[a-zA-Z0-9_]+\b", query_lower) if w]

    # 4. Direct search inside actual stored fields
    results = []
    for ev in case_evidence:
        ev_id = str(ev.get("evidence_id", ""))
        cat = str(ev.get("category", "") or "")
        desc = str(ev.get("description", "") or "")
        img_p = str(ev.get("image_path", "") or "")
        fn = os.path.basename(img_p) if img_p else ""
        fn_or_name = fn or ev_id

        # Associated metadata from links
        link_data = links_map.get(ev_id, {})
        suspect = str(link_data.get("suspect", "") or "")
        if suspect.lower() == "none":
            suspect = ""
        device = str(link_data.get("device", "") or "")
        if device.lower() == "none":
            device = ""
        ev_type_link = str(link_data.get("evidence_type", "") or "")

        # Check fields for direct matches
        field_matches = {}
        matched_fields = []
        matched_values = []

        # Check description
        if any(t in desc.lower() for t in raw_query_tokens) or query_lower in desc.lower():
            matched_fields.append("description")
            field_matches["description"] = desc
            matched_values.append(desc)

        # Check evidence_type / category
        if any(t in cat.lower() for t in raw_query_tokens) or query_lower in cat.lower():
            matched_fields.append("category")
            field_matches["category"] = cat
            matched_values.append(cat)

        if ev_type_link and (any(t in ev_type_link.lower() for t in raw_query_tokens) or query_lower in ev_type_link.lower()):
            if "evidence_type" not in matched_fields:
                matched_fields.append("evidence_type")
            field_matches["evidence_type"] = ev_type_link
            matched_values.append(ev_type_link)

        # Check evidence_id
        if any(t in ev_id.lower() for t in raw_query_tokens) or query_lower in ev_id.lower():
            matched_fields.append("evidence_id")
            field_matches["evidence_id"] = ev_id
            matched_values.append(ev_id)

        # Check filename
        if fn and (any(t in fn.lower() for t in raw_query_tokens) or query_lower in fn.lower()):
            matched_fields.append("filename")
            field_matches["filename"] = fn
            matched_values.append(fn)

        # Check suspect metadata
        if suspect and (any(t in suspect.lower() for t in raw_query_tokens) or query_lower in suspect.lower()):
            matched_fields.append("suspect_metadata")
            field_matches["suspect_metadata"] = suspect
            matched_values.append(suspect)

        # Check device metadata
        if device and (any(t in device.lower() for t in raw_query_tokens) or query_lower in device.lower()):
            matched_fields.append("device_metadata")
            field_matches["device_metadata"] = device
            matched_values.append(device)

        # Only DIRECT searchable matches belong in TEXT search
        if not matched_fields:
            continue

        # Score direct text relevance
        token_hits = 0
        all_text_matched = " ".join(matched_values).lower()
        for t in raw_query_tokens:
            if t in all_text_matched:
                token_hits += 1

        base_rel = token_hits / max(len(raw_query_tokens), 1)
        if query_lower in all_text_matched:
            base_rel = min(1.0, base_rel + 0.25)
        relevance = float(round(max(0.30, min(1.0, base_rel)), 4))

        # Confidence level
        if relevance >= 0.75:
            conf_level = "High"
            classification = "Strong Context Match"
            status = "Candidate"
        elif relevance >= 0.50:
            conf_level = "Medium"
            classification = "Moderate Context Match"
            status = "Possible Relationship"
        else:
            conf_level = "Low"
            classification = "Weak Context Match"
            status = "Requires Verification"

        # Forensic explainable reason
        field_explanations = []
        if "suspect_metadata" in matched_fields:
            field_explanations.append(f"suspect metadata '{suspect}'")
        if "device_metadata" in matched_fields:
            field_explanations.append(f"device metadata '{device}'")
        if "description" in matched_fields:
            field_explanations.append("description")
        if "evidence_type" in matched_fields or "category" in matched_fields:
            field_explanations.append(f"category/type '{cat or ev_type_link}'")
        if "evidence_id" in matched_fields:
            field_explanations.append(f"evidence ID '{ev_id}'")
        if "filename" in matched_fields:
            field_explanations.append(f"filename '{fn}'")

        reason = f"Matched query '{query_str}' in " + " and ".join(field_explanations) + "."
        matched_text_or_value = matched_values[0] if matched_values else ""

        effective_ev_type = ev_type_link or cat or "Evidence"

        results.append({
            "case_id": case_id_str,
            "search_query": query_str,
            "query": query_str,
            "query_evidence_id": None,
            "evidence_id": ev_id,
            "evidence_type": effective_ev_type,
            "category": cat or effective_ev_type,
            "filename_or_name": fn_or_name,
            "filename": fn,
            "image": img_p or None,
            "image_path": img_p or None,
            "matched_fields": matched_fields,
            "matched_text_or_value": matched_text_or_value,
            "matched_terms": [t for t in raw_query_tokens if t in all_text_matched],
            "text_relevance_score": relevance,
            "overall_relevance_score": relevance,
            "text_relevance": relevance,
            "visual_similarity_score": 0.0,
            "semantic_score": round(relevance, 2),
            "confidence_level": conf_level,
            "investigation_recommendation": "KEEP_FOR_INVESTIGATION" if conf_level == "High" else ("REVIEW_MANUALLY" if conf_level == "Medium" else "LOW_PRIORITY"),
            "classification": classification,
            "investigation_status": status,
            "sha256_exact_duplicate": False,
            "verification_required": True,
            "action": "Investigator verification required before forensic conclusion.",
            "reason": reason
        })

    # Sort deterministically: relevance descending, evidence_id ascending
    results.sort(key=lambda x: (-x["text_relevance_score"], str(x["evidence_id"])))

    try:
        limit = int(top_k)
    except (TypeError, ValueError):
        limit = 10
    limit = max(1, limit)

    results = results[:limit]
    for rank, item in enumerate(results, start=1):
        item["rank"] = rank

    if return_dict:
        if not results:
            return {
                "status": "no_data_found",
                "message": f"No relevant evidence found for '{query_str}' in {case_id_str}.",
                "case_id": case_id_str,
                "search_query": query_str,
                "results": [],
                "ranked_evidence": [],
                "results_count": 0
            }
        return {
            "status": "Success",
            "message": f"Found {len(results)} direct match(es) for '{query_str}' in {case_id_str}.",
            "case_id": case_id_str,
            "search_query": query_str,
            "results": results,
            "ranked_evidence": results,
            "results_count": len(results)
        }

    return results


def search_text_evidence(case_id, query_text, top_k=10):
    """
    Dedicated investigator-facing text search returning structured dict response
    with explicit status ('Success' or 'no_data_found').
    """
    return search_evidence_by_text(case_id, query_text, top_k=top_k, return_dict=True)


def format_investigator_text_result(item):
    """
    Format a text search match into a clean investigator-facing card dictionary.
    Exposes only useful fields: Rank, Evidence ID, Evidence Type, Filename/Name,
    Matched Field, Matched Value, Relevance Score (%), Confidence, and Reason.
    """
    if not isinstance(item, dict):
        return {}

    rank = item.get("rank", 1)
    rel_score = float(item.get("text_relevance_score", item.get("text_relevance", 0.0)))
    matched_fields = item.get("matched_fields", [])
    matched_field_str = ", ".join(matched_fields) if isinstance(matched_fields, list) else str(matched_fields)

    return {
        "rank": rank,
        "rank_display": f"RANK #{rank}",
        "evidence_id": item.get("evidence_id", ""),
        "evidence_type": item.get("evidence_type", item.get("category", "Evidence")),
        "filename_or_name": item.get("filename_or_name", item.get("filename", "")),
        "matched_field": matched_field_str,
        "matched_value": item.get("matched_text_or_value", ""),
        "relevance_score": f"{rel_score * 100:.2f}%",
        "confidence_level": item.get("confidence_level", "Medium"),
        "investigation_recommendation": item.get("investigation_recommendation", "REVIEW_MANUALLY"),
        "reason": item.get("reason", "")
    }


def render_investigator_text_card(item):
    """
    Render a clean, human-readable terminal/UI card for text search results.
    """
    data = format_investigator_text_result(item)
    if not data:
        return ""

    lines = [
        "-" * 42,
        data["rank_display"],
        "-" * 42,
        f"Evidence ID     : {data['evidence_id']}",
        f"Evidence Type   : {data['evidence_type']}",
        f"Filename / Name : {data['filename_or_name']}",
        f"Matched Field   : {data['matched_field']}",
        f"Matched Value   : {data['matched_value']}",
        f"Relevance Score : {data['relevance_score']}",
        f"Confidence      : {data['confidence_level']}",
        f"Recommendation  : {data['investigation_recommendation']}",
        f"Reason          : {data['reason']}"
    ]
    return "\n".join(lines)


def render_investigator_text_results(results):
    """
    Render complete list of text search results.
    """
    if not results:
        return "No relevant evidence found."
    return "\n\n".join(render_investigator_text_card(r) for r in results)


if __name__ == "__main__":
    print("=" * 60)
    print("DIGITAL EVIDENCE EPRA - TEXT RETRIEVAL TEST")
    print("=" * 60)

    test_queries = [
        "red car",
        "laptop used by suspect",
        "document related to case",
        "mobile phone",
        "Rahul Sharma",
        "gun weapon"
    ]

    for q in test_queries:
        res = search_evidence_by_text("CASE_DEFAULT", q, top_k=3)
        print(f"\nQuery: '{q}' -> Results: {len(res)}")
        for r in res:
            print(f"  Rank {r['rank']}: {r['evidence_id']} [{r['category']}] "
                  f"- Relevance: {r['text_relevance']:.2f} (Matches: {r['matched_terms']})")
