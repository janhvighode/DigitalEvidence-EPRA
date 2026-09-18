# ============================================================
# Digital Evidence EPRA
# Module : CBIR / Forensic Retrieval
# File   : text_retrieval.py
# Purpose: Text and context-based evidence retrieval within a
#          selected investigation case.
# Author : Member 3 (Trisha)
# ============================================================

import os
import sys
import re
import sqlite3
from datetime import datetime, timezone

CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(CURRENT_DIR, "..", ".."))
REL_GRAPH_DIR = os.path.abspath(os.path.join(PROJECT_ROOT, "ai_modules", "relationship_graph"))

for path in [PROJECT_ROOT, CURRENT_DIR, REL_GRAPH_DIR]:
    if path not in sys.path:
        sys.path.insert(0, path)

from feature_database import get_case_evidence, connect_database
try:
    from evidence_linker import get_case_links
except ImportError:
    def get_case_links(*args, **kwargs):
        return []

# Optional safe import of MetadataAdapter
try:
    from metadata_adapter import MetadataAdapter
except ImportError:
    MetadataAdapter = None

# Optional safe import of case graph builder for contextual integration
try:
    from case_graph_engine import build_case_relationship_graph
except ImportError:
    build_case_relationship_graph = None


STOP_WORDS = {
    "a", "an", "the", "and", "or", "in", "on", "at", "by", "for",
    "with", "about", "to", "from", "of", "is", "was", "are", "were",
    "this", "that", "these", "those", "it", "its", "related", "connected"
}


def tokenize(text):
    """
    Extract lowercase alphanumeric tokens, filtering stop words.
    """
    if not text:
        return []
    words = re.findall(r"\b[a-zA-Z0-9_]+\b", str(text).lower())
    return [w for w in words if w not in STOP_WORDS and len(w) > 1]


def make_snippet(text, match_term, max_len=80):
    """
    Extract a clean, concise text snippet centered around match_term.
    """
    if not text:
        return ""
    text_str = str(text).strip()
    if not match_term:
        return text_str[:max_len] + ("..." if len(text_str) > max_len else "")

    idx = text_str.lower().find(match_term.lower())
    if idx == -1:
        # Fallback: search individual words of match_term
        for w in match_term.lower().split():
            if len(w) > 2 and w in text_str.lower():
                idx = text_str.lower().find(w)
                break

    if idx == -1:
        return text_str[:max_len] + ("..." if len(text_str) > max_len else "")

    start = max(0, idx - 25)
    end = min(len(text_str), idx + len(match_term) + 40)
    snippet = text_str[start:end].strip()
    if start > 0:
        snippet = "..." + snippet
    if end < len(text_str):
        snippet = snippet + "..."
    return snippet


def extract_stored_text_content(file_path):
    """
    Extract readable text content from an evidence file or companion text/transcript file on disk.
    Supports: .txt, .log, .csv, .json, .md, .pdf, and companion .txt / _transcript.txt files.
    Never fabricates content if file does not exist or has no readable text.
    """
    if not file_path:
        return ""

    p = str(file_path)
    if not os.path.exists(p):
        p_rel = os.path.join(PROJECT_ROOT, p)
        if os.path.exists(p_rel):
            p = p_rel
        else:
            return ""

    if not os.path.isfile(p):
        return ""

    ext = os.path.splitext(p)[1].lower()
    extracted_text = []

    # 1. Plain text / structured text files
    if ext in [".txt", ".log", ".csv", ".tsv", ".json", ".xml", ".html", ".md", ".py"]:
        try:
            with open(p, "r", encoding="utf-8", errors="ignore") as f:
                content = f.read(50000)
                if content.strip():
                    extracted_text.append(content)
        except Exception:
            pass

    # 2. PDF files: extract streams or text runs
    elif ext == ".pdf":
        try:
            with open(p, "rb") as f:
                data = f.read(200000)
            pdf_matches = re.findall(rb'\(([^\(\)\\]{2,})\)\s*(?:Tj|TJ|\'|\")', data)
            if pdf_matches:
                t_str = " ".join(m.decode("latin1", errors="ignore") for m in pdf_matches)
                extracted_text.append(t_str)
            else:
                ascii_runs = re.findall(rb'[A-Za-z0-9\s,\.\-_\':;\/]{4,}', data)
                if ascii_runs:
                    extracted_text.append(" ".join(r.decode("ascii", errors="ignore") for r in ascii_runs[:50]))
        except Exception:
            pass

    # 3. Check for companion extracted text or transcript files
    base_no_ext = os.path.splitext(p)[0]
    companion_candidates = [
        base_no_ext + ".txt",
        p + ".txt",
        base_no_ext + "_transcript.txt",
        base_no_ext + ".transcript.txt",
        base_no_ext + "_extracted.txt",
        base_no_ext + ".extracted.txt",
        os.path.join(os.path.dirname(p), "notes.txt")
    ]
    for comp in companion_candidates:
        if comp != p and os.path.isfile(comp):
            try:
                with open(comp, "r", encoding="utf-8", errors="ignore") as cf:
                    c_text = cf.read(50000)
                    if c_text.strip() and c_text not in extracted_text:
                        extracted_text.append(c_text)
            except Exception:
                pass

    return "\n".join(extracted_text).strip()


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


def get_vault_evidence_records(case_id_str):
    """
    Fetch evidence records from backend evidence_vault.db if available,
    strictly isolated to case_id_str.
    """
    records = []
    vault_db_path = os.path.join(PROJECT_ROOT, "backend", "app", "evidence_vault.db")
    if os.path.isfile(vault_db_path):
        try:
            conn = sqlite3.connect(vault_db_path)
            conn.row_factory = sqlite3.Row
            cursor = conn.cursor()
            cursor.execute(
                "SELECT * FROM evidence_records WHERE case_id = ?",
                (str(case_id_str),)
            )
            for row in cursor.fetchall():
                d = dict(row)
                ev_id = str(d.get("external_evidence_id") or d.get("id") or "")
                if ev_id:
                    records.append({
                        "evidence_id": ev_id,
                        "category": d.get("evidence_type", "Evidence"),
                        "description": d.get("notes") or f"Evidence {d.get('stored_filename', '')}",
                        "image_path": d.get("file_path"),
                        "filename": d.get("original_filename") or d.get("stored_filename"),
                        "case_id": str(case_id_str),
                        "notes": d.get("notes", ""),
                        "mime_type": d.get("mime_type", ""),
                        "sha256_hash": d.get("original_sha256") or d.get("current_sha256")
                    })
            conn.close()
        except Exception:
            pass
    return records


def search_evidence_by_text(case_id, query_text, top_k=10, return_dict=False):
    """
    Search and rank evidence in a selected case matching the query text directly.
    Searches actual stored searchable fields without fabricating data:
    - Evidence ID
    - Filename / Name
    - Evidence type / Category
    - Description
    - Tags
    - Metadata (mime_type, file_type_display, dimensions)
    - Connected device information
    - Stored suspect / person information
    - Extracted document / text content (from txt, pdf, logs)
    - Existing audio / video transcripts
    - Notes

    Strict case isolation is enforced.

    Parameters
    ----------
    case_id : str
        The case ID to search within.
    query_text : str
        Arbitrary textual query keyword.
    top_k : int, optional
        Maximum number of results to return (default: 10).
    return_dict : bool, optional
        If True, return structured dict with status.
        If False, return list of result items for backward compatibility.
    """
    if not case_id or not str(case_id).strip() or not query_text or not str(query_text).strip():
        if return_dict:
            return {
                "status": "no_data_found",
                "message": f"No relevant evidence found for '{query_text}' in {case_id}.",
                "case_id": str(case_id) if case_id else None,
                "search_query": str(query_text) if query_text else "",
                "search_box_label": "Search evidence in this case...",
                "results": [],
                "ranked_evidence": [],
                "results_count": 0
            }
        return []

    case_id_str = str(case_id).strip()
    query_str = " ".join(str(query_text).strip().split())
    query_lower = query_str.lower()

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

    # 3. Fetch evidence records from backend evidence_vault if available
    vault_records = get_vault_evidence_records(case_id_str)
    for vr in vault_records:
        if vr["evidence_id"] not in existing_ev_ids:
            case_evidence.append(vr)
            existing_ev_ids.add(vr["evidence_id"])

    if not case_evidence:
        if return_dict:
            return {
                "status": "no_data_found",
                "message": f"No relevant evidence found for '{query_str}' in {case_id_str}.",
                "case_id": case_id_str,
                "search_query": query_str,
                "search_box_label": "Search evidence in this case...",
                "results": [],
                "ranked_evidence": [],
                "results_count": 0
            }
        return []

    # 3. Process query tokens (lowercase)
    raw_query_tokens = tokenize(query_str)
    if not raw_query_tokens:
        raw_query_tokens = [w for w in re.findall(r"\b[a-zA-Z0-9_]+\b", query_lower) if w]
    if not raw_query_tokens and len(query_lower) >= 1:
        raw_query_tokens = [query_lower]

    # 4. Search actual stored fields per evidence item
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
        if suspect.lower() in ["none", "null", "not available"]:
            suspect = ""
        device = str(link_data.get("device", "") or "")
        if device.lower() in ["none", "null", "not available"]:
            device = ""
        ev_type_link = str(link_data.get("evidence_type", "") or "")
        notes_link = str(link_data.get("notes", "") or "")
        tags_link = str(link_data.get("tags", "") or "")

        # Stored notes or tags on evidence object
        ev_notes = str(ev.get("notes", "") or notes_link)
        ev_tags = str(ev.get("tags", "") or tags_link)

        # Technical file metadata extraction via MetadataAdapter if available
        meta_mime = ""
        meta_file_type = ""
        meta_dims = ""
        if img_p and MetadataAdapter:
            try:
                extracted_meta = MetadataAdapter.extract_file_metadata(img_p)
                meta_mime = str(extracted_meta.get("mime_type", "") or "")
                meta_file_type = str(extracted_meta.get("file_type_display", "") or "")
                meta_dims = str(extracted_meta.get("dimensions", "") or "")
            except Exception:
                pass

        # Extracted document/text content if file exists on disk
        extracted_content = ""
        if img_p:
            extracted_content = extract_stored_text_content(img_p)

        # Check fields for direct matches
        field_matches = {}
        matched_fields = []
        matched_values = []

        # Helper matcher: phrase or token hit
        def field_has_match(field_val):
            if not field_val:
                return False
            f_low = str(field_val).lower()
            return query_lower in f_low or any(t in f_low for t in raw_query_tokens)

        # A. Check filename
        if fn and field_has_match(fn):
            matched_fields.append("filename")
            field_matches["filename"] = fn
            matched_values.append(fn)

        # B. Check evidence_id
        if ev_id and field_has_match(ev_id):
            matched_fields.append("evidence_id")
            field_matches["evidence_id"] = ev_id
            matched_values.append(ev_id)

        # C. Check description
        if desc and field_has_match(desc):
            matched_fields.append("description")
            snip = make_snippet(desc, query_str)
            field_matches["description"] = snip
            matched_values.append(snip)

        # D. Check extracted document/text content
        if extracted_content and field_has_match(extracted_content):
            matched_fields.append("extracted_text")
            snip = make_snippet(extracted_content, query_str)
            field_matches["extracted_text"] = snip
            matched_values.append(snip)

        # E. Check notes
        if ev_notes and field_has_match(ev_notes):
            matched_fields.append("notes")
            snip = make_snippet(ev_notes, query_str)
            field_matches["notes"] = snip
            matched_values.append(snip)

        # F. Check tags
        if ev_tags and field_has_match(ev_tags):
            matched_fields.append("tags")
            field_matches["tags"] = ev_tags
            matched_values.append(ev_tags)

        # G. Check category
        if cat and field_has_match(cat):
            matched_fields.append("category")
            field_matches["category"] = cat
            matched_values.append(cat)

        # H. Check evidence_type
        if ev_type_link and field_has_match(ev_type_link):
            if "evidence_type" not in matched_fields:
                matched_fields.append("evidence_type")
            field_matches["evidence_type"] = ev_type_link
            matched_values.append(ev_type_link)

        # I. Check suspect metadata
        if suspect and field_has_match(suspect):
            matched_fields.append("suspect_metadata")
            field_matches["suspect_metadata"] = suspect
            matched_values.append(suspect)

        # J. Check device metadata
        if device and field_has_match(device):
            matched_fields.append("device_metadata")
            field_matches["device_metadata"] = device
            matched_values.append(device)

        # K. Check technical metadata (mime_type, file_type_display, dimensions)
        if meta_mime and field_has_match(meta_mime):
            matched_fields.append("metadata: mime_type")
            field_matches["metadata: mime_type"] = meta_mime
            matched_values.append(meta_mime)
        if meta_file_type and field_has_match(meta_file_type):
            matched_fields.append("metadata: file_type")
            field_matches["metadata: file_type"] = meta_file_type
            matched_values.append(meta_file_type)
        if meta_dims and field_has_match(meta_dims):
            matched_fields.append("metadata: dimensions")
            field_matches["metadata: dimensions"] = meta_dims
            matched_values.append(meta_dims)

        # If no stored field matched, this item does not match direct text search
        if not matched_fields:
            continue

        # Score direct text relevance
        all_text_matched = " ".join(matched_values).lower()
        token_hits = sum(1 for t in raw_query_tokens if t in all_text_matched)
        token_ratio = token_hits / max(len(raw_query_tokens), 1)

        # Base relevance: phrase match gets top score (0.95 - 1.00)
        if query_lower in all_text_matched:
            base_rel = 0.95
        else:
            base_rel = 0.75 + (0.20 * token_ratio)

        # Boost if multiple fields match
        if len(matched_fields) > 1:
            base_rel = min(1.0, base_rel + 0.03 * (len(matched_fields) - 1))

        relevance = float(round(max(0.70, min(1.0, base_rel)), 4))

        # Confidence level
        if relevance >= 0.85:
            conf_level = "High"
            classification = "Strong Match"
            status = "Candidate"
            rec = "KEEP_FOR_INVESTIGATION"
        elif relevance >= 0.70:
            conf_level = "Medium"
            classification = "Moderate Match"
            status = "Possible Relationship"
            rec = "REVIEW_MANUALLY"
        else:
            conf_level = "Low"
            classification = "Weak Match"
            status = "Requires Verification"
            rec = "LOW_PRIORITY"

        # Forensic explainable reason
        field_explanations = []
        if "filename" in matched_fields:
            field_explanations.append(f"filename '{fn}'")
        if "evidence_id" in matched_fields:
            field_explanations.append(f"evidence ID '{ev_id}'")
        if "description" in matched_fields:
            field_explanations.append("description")
        if "extracted_text" in matched_fields:
            field_explanations.append("extracted document/text content")
        if "notes" in matched_fields:
            field_explanations.append("notes")
        if "tags" in matched_fields:
            field_explanations.append("tags")
        if "suspect_metadata" in matched_fields:
            field_explanations.append(f"suspect metadata '{suspect}'")
        if "device_metadata" in matched_fields:
            field_explanations.append(f"device metadata '{device}'")
        if "evidence_type" in matched_fields or "category" in matched_fields:
            field_explanations.append(f"category/type '{cat or ev_type_link}'")
        if any("metadata:" in mf for mf in matched_fields):
            field_explanations.append("technical metadata")

        reason = f"Direct match for query '{query_str}' in " + " and ".join(field_explanations) + "."
        matched_primary_field = matched_fields[0]
        matched_primary_value = matched_values[0] if matched_values else ""

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
            "matched_field": matched_primary_field,
            "matched_fields": matched_fields,
            "matched_value": matched_primary_value,
            "matched_text_or_value": matched_primary_value,
            "snippet": matched_primary_value,
            "matched_terms": [t for t in raw_query_tokens if t in all_text_matched],
            "text_relevance_score": relevance,
            "overall_relevance_score": relevance,
            "relevance_score": relevance,
            "relevance_score_display": f"{relevance * 100:.1f}%",
            "text_relevance": relevance,
            "visual_similarity_score": 0.0,
            "semantic_score": round(relevance, 2),
            "confidence": conf_level,
            "confidence_level": conf_level,
            "investigation_recommendation": rec,
            "classification": classification,
            "investigation_status": status,
            "sha256_exact_duplicate": False,
            "verification_required": True,
            "is_direct_match": True,
            "hops": 0,
            "action": "Investigator verification required before forensic conclusion.",
            "reason": reason,
            "relationship_view_available": True
        })

    # Sort deterministically: relevance descending, evidence_id ascending
    results.sort(key=lambda x: (-x["relevance_score"], str(x["evidence_id"])))

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
                "search_box_label": "Search evidence in this case...",
                "results": [],
                "ranked_evidence": [],
                "results_count": 0
            }
        return {
            "status": "Success",
            "message": f"Found {len(results)} relevant evidence item(s) for '{query_str}' in {case_id_str}.",
            "case_id": case_id_str,
            "search_query": query_str,
            "search_box_label": "Search evidence in this case...",
            "results": results,
            "ranked_evidence": results,
            "results_count": len(results)
        }

    return results


def search_case_evidence(case_id, query_text, top_k=10, search_mode="all", max_hops=2):
    """
    Unified investigator-facing case evidence search ("Search evidence in this case...").

    Features:
    - Enforces strict case isolation (only searches evidence within case_id).
    - Supports ANY arbitrary keyword dynamically without hardcoding.
    - Searches all actual stored data (evidence_id, filename, category, description,
      tags, notes, technical metadata, device info, suspect info, extracted text, transcripts).
    - In 'all' mode: includes real stored contextual graph connections.
    - Direct keyword matches strictly outrank weaker contextual matches.
    - Returns structured forensic report with rank, evidence_id, type, filename,
      matched_field, snippet, relevance_score, confidence, and explainable reason.
    - If nothing matches: returns status='no_data_found' and results=[].
    """
    if not case_id or not str(case_id).strip():
        return {
            "status": "error",
            "message": "case_id is mandatory for case evidence search.",
            "case_id": None,
            "search_query": str(query_text) if query_text else "",
            "search_box_label": "Search evidence in this case...",
            "results": [],
            "ranked_evidence": [],
            "results_count": 0
        }

    case_id_str = str(case_id).strip()
    query_str = " ".join(str(query_text).strip().split()) if query_text else ""

    if not query_str:
        return {
            "status": "no_data_found",
            "message": f"No relevant evidence found for '' in {case_id_str}.",
            "case_id": case_id_str,
            "search_query": "",
            "search_box_label": "Search evidence in this case...",
            "results": [],
            "ranked_evidence": [],
            "results_count": 0
        }

    # 1. Execute direct text search
    direct_matches = search_evidence_by_text(case_id_str, query_str, top_k=top_k * 2, return_dict=False)
    direct_ids = {str(item["evidence_id"]) for item in direct_matches}

    combined_results = list(direct_matches)

    # 2. Contextual search if requested
    if search_mode in ["all", "context"]:
        try:
            from context_retrieval import search_context_evidence
            ctx_dict = search_context_evidence(case_id_str, query_str, max_hops=max_hops, top_k=top_k * 2)
            if ctx_dict.get("status") == "Success":
                for ctx_item in ctx_dict.get("results", []):
                    ev_id = str(ctx_item.get("evidence_id", ctx_item.get("entity_id", "")))
                    if not ev_id or ev_id in direct_ids:
                        continue  # Direct match takes precedence

                    # Contextual matches have lower relevance score than direct matches
                    hops = ctx_item.get("hops", 1)
                    ctx_score = float(ctx_item.get("context_relevance_score", 0.65))
                    # Scale context score so it never exceeds direct matches (cap at 0.70)
                    scaled_score = round(min(0.70, ctx_score * 0.70), 4)

                    conf = "Medium" if hops == 1 else "Low"
                    rec = "REVIEW_MANUALLY" if hops == 1 else "LOW_PRIORITY"

                    combined_results.append({
                        "case_id": case_id_str,
                        "search_query": query_str,
                        "query": query_str,
                        "query_evidence_id": None,
                        "evidence_id": ev_id,
                        "evidence_type": ctx_item.get("evidence_type", "Entity"),
                        "category": ctx_item.get("evidence_type", "Entity"),
                        "filename_or_name": ctx_item.get("filename_or_name", ev_id),
                        "filename": ctx_item.get("filename", ""),
                        "image": ctx_item.get("image"),
                        "image_path": ctx_item.get("image_path"),
                        "matched_field": f"contextual_relationship ({ctx_item.get('match_type', 'GRAPH_CONNECTION')})",
                        "matched_fields": [f"context: {ctx_item.get('match_type', 'GRAPH_CONNECTION')}"],
                        "matched_value": ctx_item.get("relationship_path", ""),
                        "matched_text_or_value": ctx_item.get("relationship_path", ""),
                        "snippet": ctx_item.get("relationship_path", ""),
                        "matched_terms": [],
                        "text_relevance_score": 0.0,
                        "context_relevance_score": scaled_score,
                        "overall_relevance_score": scaled_score,
                        "relevance_score": scaled_score,
                        "relevance_score_display": f"{scaled_score * 100:.1f}%",
                        "text_relevance": 0.0,
                        "visual_similarity_score": 0.0,
                        "semantic_score": round(scaled_score, 2),
                        "confidence": conf,
                        "confidence_level": conf,
                        "investigation_recommendation": rec,
                        "classification": f"Contextual Match ({hops} hop{'s' if hops > 1 else ''})",
                        "investigation_status": "Contextual Lead",
                        "sha256_exact_duplicate": False,
                        "verification_required": True,
                        "is_direct_match": False,
                        "hops": hops,
                        "relationship_path": ctx_item.get("relationship_path", ""),
                        "action": "Investigate connection in Relationship View.",
                        "reason": ctx_item.get("reason", f"Connected via {hops} hop(s) in case relationship graph."),
                        "relationship_view_available": True
                    })
        except Exception:
            pass

    # 3. Deterministic ranking:
    # Direct matches rank above contextual matches, then by relevance_score descending, then evidence_id
    combined_results.sort(
        key=lambda x: (
            0 if x.get("is_direct_match") else 1,
            -x.get("relevance_score", 0.0),
            x.get("hops", 0),
            str(x.get("evidence_id", ""))
        )
    )

    try:
        limit = int(top_k)
    except (TypeError, ValueError):
        limit = 10
    limit = max(1, limit)

    final_results = combined_results[:limit]
    for rank, item in enumerate(final_results, start=1):
        item["rank"] = rank

    if not final_results:
        return {
            "status": "no_data_found",
            "message": f"No relevant evidence found for '{query_str}' in {case_id_str}.",
            "case_id": case_id_str,
            "search_query": query_str,
            "search_box_label": "Search evidence in this case...",
            "search_mode": search_mode,
            "results": [],
            "ranked_evidence": [],
            "results_count": 0
        }

    return {
        "status": "Success",
        "message": f"Found {len(final_results)} relevant evidence item(s) for '{query_str}' in {case_id_str}.",
        "case_id": case_id_str,
        "search_query": query_str,
        "search_box_label": "Search evidence in this case...",
        "search_mode": search_mode,
        "results": final_results,
        "ranked_evidence": final_results,
        "results_count": len(final_results)
    }


def search_text_evidence(case_id, query_text, top_k=10):
    """
    Dedicated investigator-facing text search returning structured dict response
    with explicit status ('Success' or 'no_data_found').
    """
    return search_evidence_by_text(case_id, query_text, top_k=top_k, return_dict=True)


def format_investigator_text_result(item):
    """
    Format a text search match into a clean investigator-facing card dictionary.
    Exposes: Rank, Evidence ID, Evidence Type, Filename/Name, Matched Field,
    Matched Value, Relevance Score (%), Confidence, Reason, and Relationship View link.
    """
    if not isinstance(item, dict):
        return {}

    rank = item.get("rank", 1)
    rel_score = item.get("relevance_score", item.get("text_relevance_score", 0.0))
    if isinstance(rel_score, (int, float)):
        score_disp = f"{rel_score * 100:.1f}%"
    else:
        score_disp = str(rel_score)

    matched_field_str = item.get("matched_field", "")
    if not matched_field_str:
        mf_list = item.get("matched_fields", [])
        matched_field_str = ", ".join(mf_list) if isinstance(mf_list, list) else str(mf_list)

    return {
        "rank": rank,
        "rank_display": f"RANK #{rank}",
        "evidence_id": item.get("evidence_id", ""),
        "evidence_type": item.get("evidence_type", item.get("category", "Evidence")),
        "filename_or_name": item.get("filename_or_name", item.get("filename", "")),
        "matched_field": matched_field_str,
        "matched_value": item.get("matched_value", item.get("matched_text_or_value", "")),
        "relevance_score": score_disp,
        "confidence": item.get("confidence", item.get("confidence_level", "Medium")),
        "confidence_level": item.get("confidence_level", item.get("confidence", "Medium")),
        "investigation_recommendation": item.get("investigation_recommendation", "REVIEW_MANUALLY"),
        "reason": item.get("reason", ""),
        "relationship_view_available": item.get("relationship_view_available", True)
    }


format_investigator_search_result = format_investigator_text_result


def render_investigator_search_box(case_id, current_query=""):
    """
    Render ASCII / text UI search box representation for investigator terminal / UI.
    Label: 'Search evidence in this case...'
    """
    case_str = str(case_id or "NO_CASE_SELECTED")
    q_str = str(current_query or "")
    lines = [
        "=" * 64,
        f"  CASE EVIDENCE SEARCH : [{case_str}]",
        "=" * 64,
        f"  Search Box : [ Search evidence in this case... ]",
        f"  Input      : '{q_str}'",
        "-" * 64,
        f"  Controls   : [Search]  [Clear]  [View Evidence]  [Relationship View]",
        "=" * 64
    ]
    return "\n".join(lines)


def render_investigator_text_card(item):
    """
    Render a clean, human-readable terminal/UI card for search results.
    """
    data = format_investigator_text_result(item)
    if not data:
        return ""

    lines = [
        "-" * 45,
        data["rank_display"],
        "-" * 45,
        f"Evidence ID     : {data['evidence_id']}",
        f"Evidence Type   : {data['evidence_type']}",
        f"Filename / Name : {data['filename_or_name']}",
        f"Matched Field   : {data['matched_field']}",
        f"Matched Value   : {data['matched_value']}",
        f"Relevance Score : {data['relevance_score']}",
        f"Confidence      : {data['confidence']}",
        f"Recommendation  : {data['investigation_recommendation']}",
        f"Reason          : {data['reason']}",
        f"Graph Inspector : [Open in Relationship View]"
    ]
    return "\n".join(lines)


render_investigator_search_card = render_investigator_text_card


def render_investigator_text_results(results):
    """
    Render complete list of search results.
    """
    if not results:
        return "No relevant evidence found."
    return "\n\n".join(render_investigator_text_card(r) for r in results)


render_investigator_search_results = render_investigator_text_results


if __name__ == "__main__":
    print("=" * 60)
    print("DIGITAL EVIDENCE EPRA - TEXT & CONTEXT SEARCH TEST")
    print("=" * 60)

    test_queries = [
        "mobile",
        "laptop",
        "Rahul",
        "invoice",
        "vehicle"
    ]

    for q in test_queries:
        res = search_case_evidence("CASE_DEFAULT", q, top_k=3)
        print(f"\nQuery: '{q}' -> Status: {res['status']} -> Count: {res['results_count']}")
        for r in res.get("results", []):
            print(f"  Rank #{r['rank']}: {r['evidence_id']} [{r['evidence_type']}] "
                  f"- Rel: {r['relevance_score_display']} - Field: {r['matched_field']}")
