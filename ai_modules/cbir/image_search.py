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
    semantic_score
)


# ============================================================
# SEARCH SIMILAR IMAGES
# ============================================================

def search_similar_images(
    query_image_path,
    case_evidence,
    top_k=5
):
    """
    Search for visually similar evidence images.

    The function compares the selected query image only with
    evidence supplied for the selected case.

    All case, evidence, image-path and category information
    is supplied dynamically by the backend/database.

    No case IDs, evidence IDs, image names or categories
    are hardcoded in this module.

    Parameters
    ----------
    query_image_path : str
        Path of the investigator-selected query image.

    case_evidence : list
        Evidence records belonging to the selected case.

        Expected structure:

        [
            {
                "evidence_id": "...",
                "image_path": "...",
                "category": "..."
            }
        ]

    top_k : int
        Maximum number of results to return.

    Returns
    -------
    list
        Ranked CBIR similarity results.
    """

    # --------------------------------------------------------
    # Validate query image path
    # --------------------------------------------------------

    if not query_image_path:
        print(
            "Error: Query image path was not provided."
        )
        return []

    # --------------------------------------------------------
    # Validate case evidence
    # --------------------------------------------------------

    if not isinstance(
        case_evidence,
        list
    ):
        print(
            "Error: Case evidence must be a list."
        )
        return []

    if not case_evidence:
        print(
            "No evidence available for the selected case."
        )
        return []

    # --------------------------------------------------------
    # Load query image
    # --------------------------------------------------------

    query_image = load_image(
        query_image_path
    )

    if query_image is None:
        print(
            "Unable to load query image."
        )
        return []

    # --------------------------------------------------------
    # Extract query features
    # --------------------------------------------------------

    query_features = extract_features(
        query_image
    )

    if query_features is None:
        print(
            "Unable to extract features from query image."
        )
        return []

    results = []

    # --------------------------------------------------------
    # Compare ONLY with evidence supplied for this case
    # --------------------------------------------------------

    for evidence in case_evidence:

        # ----------------------------------------------------
        # Validate evidence record
        # ----------------------------------------------------

        if not isinstance(
            evidence,
            dict
        ):
            continue

        evidence_id = evidence.get(
            "evidence_id"
        )

        image_path = evidence.get(
            "image_path"
        )

        category = evidence.get(
            "category"
        )

        # ----------------------------------------------------
        # Ignore incomplete records
        # ----------------------------------------------------

        if not evidence_id:
            continue

        if not image_path:
            continue

        # ----------------------------------------------------
        # Skip the query evidence itself
        # ----------------------------------------------------

        try:
            query_absolute_path = os.path.abspath(
                query_image_path
            )

            candidate_absolute_path = os.path.abspath(
                image_path
            )

            if (
                query_absolute_path
                ==
                candidate_absolute_path
            ):
                continue

        except (
            TypeError,
            ValueError,
            OSError
        ):
            if (
                image_path
                ==
                query_image_path
            ):
                continue

        # ----------------------------------------------------
        # Check candidate image exists
        # ----------------------------------------------------

        if not os.path.isfile(
            image_path
        ):
            print(
                f"Skipping missing evidence image: "
                f"{image_path}"
            )
            continue

        # ----------------------------------------------------
        # Load candidate image
        # ----------------------------------------------------

        candidate_image = load_image(
            image_path
        )

        if candidate_image is None:
            print(
                f"Skipping unreadable evidence image: "
                f"{image_path}"
            )
            continue

        # ----------------------------------------------------
        # Extract candidate features
        # ----------------------------------------------------

        candidate_features = extract_features(
            candidate_image
        )

        if candidate_features is None:
            continue

        # ----------------------------------------------------
        # Calculate visual similarity
        # ----------------------------------------------------

        similarity = calculate_similarity(
            query_features,
            candidate_features
        )

        # ----------------------------------------------------
        # Validate similarity score
        # ----------------------------------------------------

        try:
            similarity = float(
                similarity
            )

        except (
            TypeError,
            ValueError
        ):
            continue

        # Keep similarity inside valid range.
        similarity = max(
            0.0,
            min(
                1.0,
                similarity
            )
        )

        # ----------------------------------------------------
        # Calculate semantic score
        # ----------------------------------------------------

        semantic = semantic_score(
            similarity
        )

        # ----------------------------------------------------
        # Determine basic retrieval status
        # ----------------------------------------------------

        if similarity >= 0.95:
            status = "Duplicate"
        else:
            status = "Match"

        # ----------------------------------------------------
        # Store result
        # ----------------------------------------------------

        results.append({

            "evidence_id":
                str(evidence_id),

            "category":
                category,

            "image":
                image_path,

            "similarity":
                float(
                    round(
                        similarity,
                        4
                    )
                ),

            "semantic_score":
                float(
                    semantic
                ),

            "status":
                status
        })

    # --------------------------------------------------------
    # Rank results by actual visual similarity
    # --------------------------------------------------------

    results.sort(
        key=lambda item: item[
            "similarity"
        ],
        reverse=True
    )

    # --------------------------------------------------------
    # Validate top_k
    # --------------------------------------------------------

    try:
        limit = int(
            top_k
        )

    except (
        TypeError,
        ValueError
    ):
        limit = 5

    if limit <= 0:
        limit = 5

    # --------------------------------------------------------
    # Return top results
    # --------------------------------------------------------

    return results[
        :limit
    ]


# ============================================================
# FORMAT RESULTS FOR BACKEND / DASHBOARD
# ============================================================

def format_search_results(
    results
):
    """
    Convert raw CBIR results into a clean structure
    suitable for backend/API/dashboard responses.

    Parameters
    ----------
    results : list
        Results returned by search_similar_images().

    Returns
    -------
    list
        Formatted ranked results.
    """

    formatted = []

    if not isinstance(
        results,
        list
    ):
        return formatted

    # --------------------------------------------------------
    # Add ranking information
    # --------------------------------------------------------

    for rank, result in enumerate(
        results,
        start=1
    ):

        if not isinstance(
            result,
            dict
        ):
            continue

        formatted.append({

            "rank":
                rank,

            "evidence_id":
                result.get(
                    "evidence_id"
                ),

            "category":
                result.get(
                    "category"
                ),

            "image":
                result.get(
                    "image"
                ),

            "similarity":
                float(
                    result.get(
                        "similarity",
                        0.0
                    )
                ),

            "semantic_score":
                float(
                    result.get(
                        "semantic_score",
                        0.0
                    )
                ),

            "status":
                result.get(
                    "status",
                    "Match"
                )
        })

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