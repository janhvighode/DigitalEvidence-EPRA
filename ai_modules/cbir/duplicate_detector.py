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
    has_visual_resemblance
)


# ============================================================
# DETECT DUPLICATE / VISUAL RELATIONSHIP
# ============================================================

def detect_duplicate(similarity):
    """
    Classify a CBIR comparison result.

    IMPORTANT:
    CBIR similarity is visual evidence only.

    This function does NOT claim:
        - same person
        - same object
        - same device
        - same crime
        - same source

    High similarity means the investigator should review
    the images. It does not automatically prove identity.
    """

    try:
        similarity = float(similarity)

    except (TypeError, ValueError):
        similarity = 0.0

    similarity = max(
        0.0,
        min(
            1.0,
            similarity
        )
    )

    classification = classify_match(
        similarity
    )

    confidence = similarity_level(
        similarity
    )

    action = recommended_action(
        similarity
    )

    return {

        "similarity":
            float(
                round(
                    similarity,
                    4
                )
            ),

        "semantic_score":
            semantic_score(
                similarity
            ),

        "visual_resemblance":
            has_visual_resemblance(
                similarity
            ),

        "classification":
            classification,

        "confidence_level":
            confidence,

        "investigative_status":
            investigative_status(
                similarity
            ),

        "action":
            action
    }


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

        duplicate_result = detect_duplicate(
            similarity
        )

        result = dict(
            match
        )

        result.update(
            duplicate_result
        )

        processed_results.append(
            result
        )

    return processed_results


# ============================================================
# FILTER INVESTIGATIVELY RELEVANT RESULTS
# ============================================================

def get_investigative_candidates(
    matches
):
    """
    Return only results that deserve investigator review.

    Weak/no visual resemblance is excluded.

    Duplicate and strong/possible visual candidates
    remain available for investigation.
    """

    candidates = []

    if not matches:
        return candidates

    processed = process_duplicate_results(
        matches
    )

    for result in processed:

        status = result.get(
            "investigative_status",
            ""
        )

        if status in (
            "Duplicate Candidate",
            "Near-Duplicate Candidate",
            "Strong Visual Candidate",
            "Possible Visual Candidate"
        ):

            candidates.append(
                result
            )

    return candidates


# ============================================================
# DUPLICATE ONLY FILTER
# ============================================================

def get_duplicate_candidates(
    matches
):
    """
    Return only very high similarity candidates.

    These still require verification before evidence
    is merged.
    """

    duplicates = []

    if not matches:
        return duplicates

    processed = process_duplicate_results(
        matches
    )

    for result in processed:

        classification = result.get(
            "classification"
        )

        if classification in (
            "Exact Duplicate",
            "Near Duplicate"
        ):

            duplicates.append(
                result
            )

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