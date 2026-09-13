# ============================================================
# Digital Evidence EPRA
# Module : CBIR
# File   : image_search.py
# Purpose: Search visually similar evidence images
# Author : Member 3 (Trisha)
# ============================================================

import os

from feature_extractor import (
    load_image,
    extract_features
)

from similarity import (
    calculate_similarity,
    compute_multi_signal_similarity,
    semantic_score,
    similarity_level,
    classify_match,
    investigative_status,
    recommended_action,
    is_verification_required,
    load_feature_vector
)

from semantic_score import compute_semantic_score
from hash_verifier import are_exact_duplicates


# ============================================================
# SEARCH SIMILAR IMAGES
# ============================================================

def search_similar_images(
    query_image_path,
    case_evidence=None,
    top_k=5,
    case_id=None,
    query_evidence_id=None
):
    """
    Search for visually similar evidence images strictly within a selected case.

    Parameters
    ----------
    query_image_path : str
        Path of the investigator-selected query image.

    case_evidence : list, optional
        Evidence records belonging strictly to the selected case.
        If None, dynamically fetched from the database using case_id.

    top_k : int or None
        Maximum number of results to return. If None, returns all ranked candidates.

    case_id : str, optional
        Case identifier for strict case isolation audit trail.

    query_evidence_id : str, optional
        The evidence ID of the query item (used to exclude self-comparison).

    Returns
    -------
    list
        Ranked, forensic-safe similarity results with multi-signal breakdown.
    """

    # --------------------------------------------------------
    # Validate query image path
    # --------------------------------------------------------

    if not query_image_path:
        print("Error: Query image path was not provided.")
        return []

    # --------------------------------------------------------
    # Validate case evidence (fetch dynamically from database if None)
    # --------------------------------------------------------

    if case_evidence is None and case_id:
        try:
            from feature_database import get_case_evidence
            case_evidence = get_case_evidence(str(case_id).strip())
        except Exception as e:
            print(f"Error fetching case evidence for {case_id}: {e}")
            return []

    if not isinstance(case_evidence, list):
        print("Error: Case evidence must be a list.")
        return []

    if not case_evidence:
        print("No evidence available for the selected case.")
        return []

    # --------------------------------------------------------
    # Load query image
    # --------------------------------------------------------

    query_image = load_image(query_image_path)
    if query_image is None:
        print(f"Unable to load query image: {query_image_path}")
        return []

    # --------------------------------------------------------
    # Extract query features
    # --------------------------------------------------------

    query_features = extract_features(query_image)
    if query_features is None:
        print("Unable to extract features from query image.")
        return []

    # --------------------------------------------------------
    # Auto-resolve query_evidence_id if not explicitly provided
    # --------------------------------------------------------
    if not query_evidence_id and query_image_path:
        for ev in case_evidence:
            if isinstance(ev, dict) and ev.get("image_path"):
                try:
                    if os.path.abspath(ev["image_path"]) == os.path.abspath(query_image_path):
                        query_evidence_id = str(ev.get("evidence_id"))
                        break
                except (TypeError, ValueError, OSError):
                    if ev["image_path"] == query_image_path:
                        query_evidence_id = str(ev.get("evidence_id"))
                        break

    results = []

    # --------------------------------------------------------
    # Compare ONLY with evidence supplied for this case
    # --------------------------------------------------------

    for evidence in case_evidence:

        if not isinstance(evidence, dict):
            continue

        evidence_id = evidence.get("evidence_id")
        image_path = evidence.get("image_path")
        category = evidence.get("category")
        ev_case_id = evidence.get("case_id", case_id)
        ev_desc = evidence.get("description", "")

        if not evidence_id or not image_path:
            continue

        # ----------------------------------------------------
        # Skip the query evidence itself (Self-Match Exclusion)
        # ----------------------------------------------------

        if query_evidence_id and str(evidence_id) == str(query_evidence_id):
            continue

        try:
            if os.path.abspath(query_image_path) == os.path.abspath(image_path):
                continue
        except (TypeError, ValueError, OSError):
            if image_path == query_image_path:
                continue

        # ----------------------------------------------------
        # Check candidate image exists
        # ----------------------------------------------------

        if not os.path.isfile(image_path):
            continue

        # ----------------------------------------------------
        # Cryptographic Hash (SHA-256) Check
        # ----------------------------------------------------

        is_exact_dup, query_hash, cand_hash = are_exact_duplicates(
            query_image_path,
            image_path
        )

        cat_str = str(category).lower() if category else ""
        is_person = ("person" in cat_str) or ("person" in str(evidence_id).lower())

        if is_exact_dup:
            similarity = 1.0
            is_exact_hash_match = True
            signals = {
                "edge_similarity": 1.0,
                "orb_similarity": 1.0,
                "color_similarity": 1.0,
                "grayscale_similarity": 1.0,
                "hist_similarity": 1.0,
                "gray_similarity": 1.0,
                "base_score": 1.0,
                "final_score": 1.0,
                "safeguard_applied": False
            }
        else:
            is_exact_hash_match = False
            candidate_features = None

            f_path = evidence.get("feature_path")
            if f_path and os.path.isfile(f_path):
                candidate_features = load_feature_vector(f_path)

            if candidate_features is None:
                candidate_image = load_image(image_path)
                if candidate_image is None:
                    continue
                candidate_features = extract_features(candidate_image)

            if candidate_features is None:
                continue

            similarity, signals = compute_multi_signal_similarity(
                query_features,
                candidate_features
            )

        similarity = float(round(max(0.0, min(1.0, float(similarity))), 4))
        classification = classify_match(similarity, is_exact_hash_match=is_exact_hash_match, is_person=is_person)
        status = investigative_status(similarity, is_exact_hash_match=is_exact_hash_match, is_person=is_person)
        action = recommended_action(similarity, is_exact_hash_match=is_exact_hash_match, is_person=is_person)
        verification_req = is_verification_required(similarity, is_exact_hash_match=is_exact_hash_match, is_person=is_person)

        if is_exact_hash_match:
            reason = "SHA-256 hashes are identical; files are exact bit-for-bit duplicates."
        elif is_person and similarity >= 0.93:
            reason = f"Very strong visual resemblance candidate (score {similarity:.4f}). Visual evidence only; does NOT confirm identity; verification required."
        elif is_person and similarity >= 0.85:
            reason = f"Strong visual resemblance candidate (score {similarity:.4f}). Visual evidence only; does NOT confirm identity; verification required."
        elif is_person and similarity >= 0.50:
            reason = f"Possible visual resemblance candidate (score {similarity:.4f}). Visual evidence only; does NOT confirm identity; verification required."
        elif similarity >= 0.93:
            reason = f"Very strong visual candidate (score {similarity:.4f}). Verification required."
        elif similarity >= 0.85:
            reason = f"Strong visual candidate (score {similarity:.4f}) supported by multi-signal agreement. Verification required."
        elif similarity >= 0.70:
            reason = f"Possible visual resemblance (score {similarity:.4f}). Verification required."
        elif similarity >= 0.50:
            reason = f"Weak visual resemblance (score {similarity:.4f}). Verification required."
        else:
            reason = "No significant visual match found."

        # Compute investigator-friendly confidence and recommendation
        if is_exact_hash_match or similarity >= 0.85:
            confidence_level = "High"
        elif similarity >= 0.70:
            confidence_level = "Medium"
        else:
            confidence_level = "Low"

        if is_exact_hash_match:
            investigation_recommendation = "KEEP_FOR_INVESTIGATION"
        elif similarity >= 0.85:
            investigation_recommendation = "KEEP_FOR_INVESTIGATION"
        elif similarity >= 0.70:
            investigation_recommendation = "REVIEW_MANUALLY"
        elif similarity >= 0.50:
            investigation_recommendation = "LOW_PRIORITY"
        else:
            investigation_recommendation = "NOT_RECOMMENDED"

        query_fn = os.path.basename(query_image_path) if query_image_path else ""
        cand_fn = os.path.basename(image_path) if image_path else ""

        results.append({
            "case_id": ev_case_id,
            "query_evidence_id": query_evidence_id,
            "query_filename": query_fn,
            "candidate_evidence_id": str(evidence_id),
            "candidate_filename": cand_fn,
            "filename_or_name": cand_fn or str(evidence_id),
            "evidence_id": str(evidence_id),
            "evidence_type": category or "Image",
            "category": category,
            "image": image_path,
            "image_path": image_path,
            "description": ev_desc,
            "visual_similarity_score": similarity,
            "text_relevance_score": 0.0,
            "overall_relevance_score": similarity,
            "edge_similarity": signals.get("edge_similarity", similarity),
            "orb_similarity": signals.get("orb_similarity", similarity),
            "color_similarity": signals.get("color_similarity", similarity),
            "grayscale_similarity": signals.get("grayscale_similarity", similarity),
            "similarity": similarity,
            "semantic_score": compute_semantic_score(
                classification=classification,
                similarity_score=similarity,
                is_exact_hash_match=is_exact_hash_match
            ),
            "similarity_level": similarity_level(similarity),
            "classification": classification,
            "confidence_level": confidence_level,
            "investigation_recommendation": investigation_recommendation,
            "sha256_exact_duplicate": bool(is_exact_hash_match),
            "is_exact_hash_match": bool(is_exact_hash_match),
            "verification_required": bool(verification_req),
            "investigation_status": status,
            "status": classification,
            "action": action,
            "reason": reason,
            "sha256_hash": cand_hash,
            "query_sha256_hash": query_hash,
            "signals": signals
        })

    # --------------------------------------------------------
    # Deterministic Ranking: score descending, then candidate_evidence_id ascending
    # --------------------------------------------------------

    results.sort(
        key=lambda item: (-item["visual_similarity_score"], str(item["evidence_id"]))
    )

    # Assign consecutive, deterministic rank (1, 2, ...) to ALL evaluated candidates
    for rank, item in enumerate(results, start=1):
        item["rank"] = rank

    # --------------------------------------------------------
    # Apply top_k slicing ONLY AFTER all candidates have been compared and ranked
    # --------------------------------------------------------

    if top_k is not None:
        try:
            limit = int(top_k)
            if limit > 0:
                return results[:limit]
        except (TypeError, ValueError):
            pass

    return results


# ============================================================
# FORMAT RESULTS FOR BACKEND / DASHBOARD / INVESTIGATOR
# ============================================================

def format_investigator_image_result(result_item):
    """
    Format a single candidate comparison into a clean, clutter-free investigator-facing card dictionary.
    Exposes RANK first, percentage-formatted scores, and hides raw SHA hashes and technical paths.
    """
    if not isinstance(result_item, dict):
        return {}

    rank = result_item.get("rank", 1)
    q_id = result_item.get("query_evidence_id", "")
    q_fn = result_item.get("query_filename", "")
    c_id = result_item.get("candidate_evidence_id", result_item.get("evidence_id", ""))
    c_fn = result_item.get("candidate_filename", result_item.get("filename_or_name", ""))

    vis_score = float(result_item.get("visual_similarity_score", result_item.get("similarity", 0.0)))
    sem_score = float(result_item.get("semantic_score", 0.0))

    vis_pct = f"{vis_score * 100:.2f}%"
    sem_val = sem_score * 100
    sem_pct = f"{sem_val:.0f}%" if sem_val % 1 == 0 else f"{sem_val:.2f}%"

    edge_score = float(result_item.get("edge_similarity", vis_score))
    orb_score = float(result_item.get("orb_similarity", vis_score))
    color_score = float(result_item.get("color_similarity", vis_score))
    gray_score = float(result_item.get("grayscale_similarity", vis_score))

    is_dup = bool(result_item.get("sha256_exact_duplicate", False))
    ver_req = bool(result_item.get("verification_required", True))

    return {
        "rank": rank,
        "rank_display": f"RANK #{rank}",
        "query_image": {
            "evidence_id": q_id,
            "filename": q_fn
        },
        "compared_evidence": {
            "evidence_id": c_id,
            "filename": c_fn
        },
        "match_analysis": {
            "visual_similarity_score": vis_pct,
            "semantic_score": sem_pct,
            "classification": result_item.get("classification", "No Significant Visual Match"),
            "confidence_level": result_item.get("confidence_level", "Low")
        },
        "investigation": {
            "recommendation": result_item.get("investigation_recommendation", "REVIEW_MANUALLY"),
            "exact_duplicate": "EXACT DUPLICATE — VERIFIED" if is_dup else "No",
            "duplicate_status": "EXACT DUPLICATE — VERIFIED" if is_dup else None,
            "verification_required": "Yes" if ver_req else "No",
            "reason": result_item.get("reason", "")
        },
        "detailed_visual_analysis": {
            "edge_similarity": f"{edge_score * 100:.2f}%",
            "orb_similarity": f"{orb_score * 100:.2f}%",
            "color_similarity": f"{color_score * 100:.2f}%",
            "grayscale_similarity": f"{gray_score * 100:.2f}%"
        }
    }


def render_investigator_image_card(result_item):
    """
    Render a clean, human-readable card for an investigator.
    Displays RANK # first, hides raw SHA hashes and technical paths.
    """
    card_data = format_investigator_image_result(result_item)
    if not card_data:
        return ""

    rank_disp = card_data["rank_display"]
    q = card_data["query_image"]
    c = card_data["compared_evidence"]
    m = card_data["match_analysis"]
    inv = card_data["investigation"]
    det = card_data["detailed_visual_analysis"]

    inv_lines = [
        "Investigation:",
        f"  - Recommendation          : {inv['recommendation']}",
    ]
    if inv.get("duplicate_status"):
        inv_lines.append(f"  - Duplicate Status        : {inv['duplicate_status']}")
    inv_lines.extend([
        f"  - Verification Required   : {inv['verification_required']}",
        f"  - Reason                  : {inv['reason']}"
    ])

    lines = [
        "-" * 42,
        rank_disp,
        "-" * 42,
        "Query Image:",
        f"  - Evidence ID : {q['evidence_id']}",
        f"  - Filename    : {q['filename']}",
        "",
        "Compared Evidence:",
        f"  - Evidence ID : {c['evidence_id']}",
        f"  - Filename    : {c['filename']}",
        "",
        "Match Analysis:",
        f"  - Visual Similarity Score : {m['visual_similarity_score']}",
        f"  - Semantic Score          : {m['semantic_score']}",
        f"  - Classification          : {m['classification']}",
        f"  - Confidence Level        : {m['confidence_level']}",
        "",
        *inv_lines,
        "",
        "Detailed Visual Analysis:",
        f"  - Edge Similarity         : {det['edge_similarity']}",
        f"  - ORB Similarity          : {det['orb_similarity']}",
        f"  - Color Similarity        : {det['color_similarity']}",
        f"  - Grayscale Similarity    : {det['grayscale_similarity']}"
    ]
    return "\n".join(lines)


def render_investigator_image_results(results):
    """
    Render complete list of candidate results in ranked order.
    """
    if not results:
        return "No similar evidence found for the selected query."

    cards = []
    for item in results:
        card_str = render_investigator_image_card(item)
        if card_str:
            cards.append(card_str)

    return "\n\n".join(cards)


def format_search_results(results, clean_display=False):
    """
    Convert raw CBIR results into structured, ranked dictionaries.
    If clean_display is True, returns clean investigator cards without internal clutter.
    If clean_display is False (default), preserves all forensic fields and attaches
    human-friendly display fields.
    """
    formatted = []
    if not isinstance(results, list):
        return formatted

    for rank, result in enumerate(results, start=1):
        if not isinstance(result, dict):
            continue

        if clean_display:
            item = format_investigator_image_result(result)
            item["rank"] = rank
            item["rank_display"] = f"RANK #{rank}"
            formatted.append(item)
        else:
            item = dict(result)
            item["rank"] = item.get("rank", rank)
            item["rank_display"] = f"RANK #{item['rank']}"
            vis_val = float(item.get("visual_similarity_score", item.get("similarity", 0.0)))
            item["visual_similarity_percent"] = f"{vis_val * 100:.2f}%"
            sem_val = float(item.get("semantic_score", 0.0)) * 100
            item["semantic_score_percent"] = f"{sem_val:.0f}%" if sem_val % 1 == 0 else f"{sem_val:.2f}%"
            item["exact_duplicate_display"] = "Yes" if item.get("sha256_exact_duplicate") else "No"
            item["verification_required_display"] = "Yes" if item.get("verification_required") else "No"
            item["investigator_card"] = format_investigator_image_result(item)
            formatted.append(item)

    return formatted


# ============================================================
# UTILITY: CHECK SEARCH RESULT COUNT
# ============================================================

def has_search_results(
    results
):
    """
    Check whether CBIR produced any valid results.

    Returns
    -------
    bool
        True if at least one result exists.
    """

    return (
        isinstance(
            results,
            list
        )
        and
        len(results) > 0
    )


# ============================================================
# UTILITY: GET BEST MATCH
# ============================================================

def get_best_match(
    results
):
    """
    Return the highest-ranked CBIR result.

    Results are expected to already be sorted by similarity.

    Returns
    -------
    dict or None
        Best matching evidence.
    """

    if not has_search_results(
        results
    ):
        return None

    return results[0]


# ============================================================
# IMPORTANT DESIGN NOTE
# ============================================================

"""
CBIR DESIGN:

1. The selected case is NOT hardcoded here.

2. Evidence IDs are NOT hardcoded here.

3. Image names are NOT hardcoded here.

4. Categories are NOT hardcoded here.

5. Image paths are NOT hardcoded here.

6. The backend/database supplies case_evidence dynamically.

7. CBIR compares the query image ONLY against the supplied
   evidence records belonging to the selected case.

8. Category is stored as contextual information but is NOT
   used to artificially increase visual similarity.

9. Visual similarity is calculated by the similarity module.

10. Results are ranked using the calculated similarity score.

11. This module does not directly access every case in the
    system.

12. Final integrated workflow:

        Investigator
              |
              v
        Selected Case
              |
              v
        Backend / Database
              |
              v
        case_evidence
              |
              v
        CBIR Image Search
              |
              v
        Ranked Similar Evidence
"""


# ============================================================
# LOCAL TESTING
# ============================================================

if __name__ == "__main__":

    print("=" * 70)
    print("DIGITAL EVIDENCE EPRA")
    print("CBIR IMAGE SEARCH MODULE TEST")
    print("=" * 70)

    print()
    print(
        "This module requires case evidence to be supplied"
    )
    print(
        "by the CBIR pipeline/backend."
    )
    print()
    print(
        "No hardcoded case or evidence records are used."
    )

    print("=" * 70)