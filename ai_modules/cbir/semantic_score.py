# ======================================================
# Digital Evidence EPRA
# Module : CBIR
# File   : semantic_score.py
# Author : Member 3
# Purpose: Generate semantic score for EPRA engine.
# ======================================================

from duplicate_detector import detect_duplicate


def compute_semantic_score(classification=None, similarity_score=0.0, is_exact_hash_match=False):
    """
    Compute transparent discrete semantic score based on verified forensic match classification.
    No black-box or unsupported embedding AI claimed.
    """
    if is_exact_hash_match or (classification and "Exact Duplicate" in str(classification)):
        return 1.00

    if not classification:
        dup = detect_duplicate(similarity_score, is_exact_hash_match=is_exact_hash_match)
        classification = dup.get("classification", "No Significant Visual Match")

    cls_str = str(classification)
    if "Exact Duplicate" in cls_str:
        return 1.00
    elif "Near Duplicate" in cls_str or "Very Strong Visual Match" in cls_str:
        return 0.95
    elif "Strong Visual Match" in cls_str or "Highly Similar" in cls_str or "Strong Context Match" in cls_str:
        return 0.85
    elif "Possible Visual Resemblance" in cls_str or "Related Evidence" in cls_str or "Moderate Context Match" in cls_str:
        return 0.70
    elif "Weak Visual Resemblance" in cls_str or "Weak Context Match" in cls_str:
        return 0.50
    elif "No Significant" in cls_str:
        return 0.40
    else:
        return 0.40


def generate_semantic_score(evidence_id, similarity_score=0.0, classification=None, is_exact_hash_match=False):
    """
    Generate semantic score for EPRA.
    Calculated transparently from forensic match tier without fabricating data.
    """
    sem_score = compute_semantic_score(
        classification=classification,
        similarity_score=similarity_score,
        is_exact_hash_match=is_exact_hash_match
    )

    if not classification:
        dup = detect_duplicate(similarity_score, is_exact_hash_match=is_exact_hash_match)
        classification = dup.get("classification", "No Significant Visual Match")

    return {
        "evidence_id": str(evidence_id) if evidence_id else "",
        "semantic_score": round(sem_score, 2),
        "classification": classification,
        "confidence": "High" if sem_score >= 0.85 else ("Medium" if sem_score >= 0.70 else "Low")
    }


# ------------------------------------------------------
# Testing
# ------------------------------------------------------

if __name__ == "__main__":

    tests = [

        ("EV_PERSON2", 0.99),

        ("EV_PERSON5", 0.93),

        ("EV_GUN1", 0.82),

        ("EV_CAR1", 0.69),

        ("EV_LAPTOP1", 0.40)

    ]

    print("=" * 60)
    print("SEMANTIC SCORE ENGINE")
    print("=" * 60)

    for evidence_id, similarity in tests:

        result = generate_semantic_score(
            evidence_id,
            similarity
        )

        print()

        print(result)