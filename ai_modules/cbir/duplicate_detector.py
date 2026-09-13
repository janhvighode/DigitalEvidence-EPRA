# ============================================================
# Digital Evidence EPRA
# Module : CBIR
# File   : duplicate_detector.py
# Purpose: Conservative duplicate and visual-match detection
# Author : Member 3 (Trisha)
# ============================================================

from similarity import (
    similarity_level,
    semantic_score,
    classify_match,
    investigative_status,
    recommended_action,
    has_visual_resemblance,
    is_verification_required,
    compute_confidence_level,
    compute_investigation_recommendation
)


# ============================================================
# DETECT DUPLICATE / VISUAL RELATIONSHIP
# ============================================================

def detect_duplicate(similarity, is_exact_hash_match=False, is_person=False, signals=None):
    """
    Classify a CBIR comparison result.

    IMPORTANT FORENSIC RULE:
    CBIR similarity is visual evidence only.
    This function does NOT claim identity or same person.
    Exact duplicate status requires cryptographic SHA-256 verification bit-for-bit.
    """

    try:
        similarity = float(similarity)
    except (TypeError, ValueError):
        similarity = 0.0

    similarity = max(0.0, min(1.0, similarity))

    classification = classify_match(
        similarity,
        is_exact_hash_match=is_exact_hash_match,
        is_person=is_person
    )

    confidence = compute_confidence_level(similarity, is_exact_hash_match=is_exact_hash_match)
    inv_rec = compute_investigation_recommendation(classification=classification, score=similarity, is_exact_hash_match=is_exact_hash_match)

    action = recommended_action(
        similarity,
        is_exact_hash_match=is_exact_hash_match,
        is_person=is_person
    )

    status = investigative_status(
        similarity,
        is_exact_hash_match=is_exact_hash_match,
        is_person=is_person
    )

    ver_req = is_verification_required(
        similarity,
        is_exact_hash_match=is_exact_hash_match,
        is_person=is_person
    )

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

    res = {
        "visual_similarity_score": float(round(similarity, 4)),
        "similarity": float(round(similarity, 4)),
        "semantic_score": semantic_score(similarity),
        "similarity_level": similarity_level(similarity),
        "visual_resemblance": has_visual_resemblance(similarity),
        "classification": classification,
        "confidence_level": confidence,
        "investigation_recommendation": inv_rec,
        "investigation_status": status,
        "action": action,
        "verification_required": bool(ver_req),
        "sha256_exact_duplicate": bool(is_exact_hash_match),
        "is_exact_hash_match": bool(is_exact_hash_match),
        "reason": reason
    }

    if signals and isinstance(signals, dict):
        res["edge_similarity"] = signals.get("edge_similarity", float(round(similarity, 4)))
        res["orb_similarity"] = signals.get("orb_similarity", float(round(similarity, 4)))
        res["color_similarity"] = signals.get("color_similarity", float(round(similarity, 4)))
        res["grayscale_similarity"] = signals.get("grayscale_similarity", float(round(similarity, 4)))
        res["signals"] = signals

    return res


# ============================================================
# PROCESS CBIR MATCHES
# ============================================================

def process_duplicate_results(
    matches
):
    """
    Process CBIR similarity results.

    Each result receives conservative duplicate/
    visual-resemblance classification.

    Existing evidence information is preserved.
    """

    processed_results = []

    if not matches:
        return processed_results

    for match in matches:

        if not isinstance(
            match,
            dict
        ):
            continue

        try:

            similarity = float(
                match.get(
                    "similarity",
                    0.0
                )
            )

        except (
            TypeError,
            ValueError
        ):

            similarity = 0.0

        is_exact_hash_match = bool(
            match.get("sha256_exact_duplicate")
            or match.get("is_exact_hash_match", False)
        )

        cat = str(match.get("category", "")).lower()
        ev_type = str(match.get("evidence_type", "")).lower()
        is_person = ("person" in cat) or ("person" in ev_type)
        signals = match.get("signals")

        duplicate_result = detect_duplicate(
            similarity,
            is_exact_hash_match=is_exact_hash_match,
            is_person=is_person,
            signals=signals
        )

        result = dict(match)
        result.update(duplicate_result)
        processed_results.append(result)

    return processed_results


# ============================================================
# FILTER INVESTIGATIVELY RELEVANT RESULTS
# ============================================================

def get_investigative_candidates(matches):
    """
    Return only results that deserve investigator review.
    Weak or no-match results are excluded.
    """
    candidates = []
    if not matches:
        return candidates

    processed = process_duplicate_results(matches)

    for result in processed:
        status = result.get("investigative_status", "")
        if status in ("Exact Duplicate", "Candidate", "Possible Relationship"):
            candidates.append(result)

    return candidates


# ============================================================
# DUPLICATE ONLY FILTER
# ============================================================

def get_duplicate_candidates(matches):
    """
    Return only exact or near duplicate candidates.
    """
    duplicates = []
    if not matches:
        return duplicates

    processed = process_duplicate_results(matches)

    for result in processed:
        classification = result.get("classification", "")
        if classification in ("Exact Duplicate", "Near Duplicate"):
            duplicates.append(result)

    return duplicates


# ============================================================
# TEST
# ============================================================

if __name__ == "__main__":

    print("=" * 70)
    print("DIGITAL EVIDENCE EPRA")
    print("CBIR DUPLICATE DETECTOR TEST")
    print("=" * 70)

    test_matches = [

        {
            "source_evidence_id":
                "EV_PERSON1",

            "target_evidence_id":
                "EV_PERSON2",

            "target_image":
                "person2.jpg",

            "similarity":
                0.97
        },

        {
            "source_evidence_id":
                "EV_PERSON1",

            "target_evidence_id":
                "EV_PERSON3",

            "target_image":
                "person3.jpg",

            "similarity":
                0.87
        },

        {
            "source_evidence_id":
                "EV_PERSON1",

            "target_evidence_id":
                "EV_PERSON4",

            "target_image":
                "person4.jpg",

            "similarity":
                0.78
        },

        {
            "source_evidence_id":
                "EV_PERSON1",

            "target_evidence_id":
                "EV_PERSON5",

            "target_image":
                "person5.jpg",

            "similarity":
                0.45
        }
    ]

    print()

    print(
        "PROCESSING TEST RESULTS"
    )

    print(
        "=" * 70
    )

    processed = process_duplicate_results(
        test_matches
    )

    for result in processed:

        print()

        print(
            f"Source Evidence : "
            f"{result.get('source_evidence_id')}"
        )

        print(
            f"Target Evidence : "
            f"{result.get('target_evidence_id')}"
        )

        print(
            f"Target Image    : "
            f"{result.get('target_image')}"
        )

        print(
            f"Similarity      : "
            f"{result.get('similarity', 0.0):.4f}"
        )

        print(
            f"Classification   : "
            f"{result.get('classification')}"
        )

        print(
            f"Confidence Level : "
            f"{result.get('confidence_level')}"
        )

        print(
            f"Investigation   : "
            f"{result.get('investigative_status')}"
        )

        print(
            f"Action           : "
            f"{result.get('action')}"
        )

        print(
            "-" * 70
        )

    print()

    print(
        "INVESTIGATIVE CANDIDATES"
    )

    print(
        "=" * 70
    )

    candidates = get_investigative_candidates(
        test_matches
    )

    for candidate in candidates:

        print(
            f"{candidate['source_evidence_id']} "
            f"--> "
            f"{candidate['target_evidence_id']} "
            f"| "
            f"{candidate['similarity']:.2f} "
            f"| "
            f"{candidate['classification']}"
        )

    print()

    print(
        "DUPLICATE CANDIDATES"
    )

    print(
        "=" * 70
    )

    duplicates = get_duplicate_candidates(
        test_matches
    )

    for duplicate in duplicates:

        print(
            f"{duplicate['source_evidence_id']} "
            f"--> "
            f"{duplicate['target_evidence_id']} "
            f"| "
            f"{duplicate['similarity']:.2f} "
            f"| "
            f"{duplicate['classification']}"
        )

    print()

    print("=" * 70)

    print(
        "IMPORTANT:"
    )

    print(
        "CBIR results are investigative assistance only."
    )

    print(
        "They must not be treated as proof of identity."
    )

    print("=" * 70)