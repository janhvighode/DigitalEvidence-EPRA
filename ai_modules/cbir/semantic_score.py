# ======================================================
# Digital Evidence EPRA
# Module : CBIR
# File   : semantic_score.py
# Author : Member 3
# Purpose: Generate semantic score for EPRA engine.
# ======================================================

from duplicate_detector import classify_similarity


def generate_semantic_score(evidence_id, similarity_score):
    """
    Generate semantic score for EPRA.
    """

    duplicate_result = classify_similarity(similarity_score)

    classification = duplicate_result["classification"]

    if classification == "Exact Duplicate":
        semantic_score = 1.00

    elif classification == "Near Duplicate":
        semantic_score = 0.95

    elif classification == "Highly Similar":
        semantic_score = 0.85

    elif classification == "Related Evidence":
        semantic_score = 0.70

    else:
        semantic_score = 0.40

    return {

        "evidence_id": evidence_id,

        "semantic_score": round(semantic_score, 2),

        "classification": classification,

        "confidence": duplicate_result["confidence"]

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