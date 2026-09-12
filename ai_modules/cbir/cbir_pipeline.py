# ============================================================
# Digital Evidence EPRA
# Module : CBIR
# File   : cbir_pipeline.py
# Purpose: Standalone end-to-end CBIR pipeline
# Author : Member 3
# ============================================================

import os
import sys
import json


# ============================================================
# PROJECT PATH
# ============================================================

CURRENT_DIR = os.path.dirname(
    os.path.abspath(__file__)
)

PROJECT_ROOT = os.path.abspath(
    os.path.join(
        CURRENT_DIR,
        "..",
        ".."
    )
)

if PROJECT_ROOT not in sys.path:
    sys.path.insert(
        0,
        PROJECT_ROOT
    )


# ============================================================
# CBIR IMPORTS
# ============================================================

from feature_extractor import (
    load_image,
    extract_features
)

from similarity import (
    calculate_similarity,
    compute_multi_signal_similarity,
    semantic_score,
    classify_match,
    investigative_status,
    recommended_action,
    is_verification_required
)

from hash_verifier import are_exact_duplicates

from relationship_engine import (
    generate_relationships
)

from image_search import render_investigator_image_card


# ============================================================
# IMAGE VALIDATION
# ============================================================

SUPPORTED_FORMATS = (
    ".jpg",
    ".jpeg",
    ".png",
    ".bmp",
    ".webp"
)


def is_valid_image_path(image_path):
    """
    Check whether the supplied path points to
    a supported image file.
    """

    if not image_path:
        return False

    if not os.path.isfile(image_path):
        return False

    extension = os.path.splitext(
        image_path
    )[1].lower()

    return extension in SUPPORTED_FORMATS


# ============================================================
# LOAD CASE EVIDENCE
# ============================================================

def load_case_evidence(case_folder):
    """
    Dynamically load all evidence images from a case folder.

    Expected structure:

        case_folder/
            image1.jpg
            image2.jpg
            image3.jpg

    No evidence IDs or image names are hardcoded.
    """

    evidence = []

    if not os.path.isdir(case_folder):
        return evidence

    for file_name in sorted(
        os.listdir(case_folder)
    ):

        image_path = os.path.join(
            case_folder,
            file_name
        )

        if not is_valid_image_path(
            image_path
        ):
            continue

        evidence_id = os.path.splitext(
            file_name
        )[0]

        evidence.append({

            "evidence_id":
                evidence_id,

            "image_path":
                image_path,

            "category":
                os.path.basename(
                    case_folder
                )
        })

    return evidence


# ============================================================
# SEARCH CASE EVIDENCE
# ============================================================

def search_case_evidence(
    query_evidence,
    case_evidence,
    top_k=5
):
    """
    Compare the query evidence against all
    other evidence belonging to the same case.
    """

    query_image_path = query_evidence[
        "image_path"
    ]

    query_image = load_image(
        query_image_path
    )

    if query_image is None:
        return []

    query_features = extract_features(
        query_image
    )

    if query_features is None:
        return []

    results = []

    for evidence in case_evidence:

        evidence_id = evidence.get(
            "evidence_id"
        )

        image_path = evidence.get(
            "image_path"
        )

        if not evidence_id:
            continue

        if not image_path:
            continue

        # Do not compare image with itself
        if os.path.abspath(
            image_path
        ) == os.path.abspath(
            query_image_path
        ):
            continue

        candidate_image = load_image(
            image_path
        )

        if candidate_image is None:
            continue

        candidate_features = extract_features(
            candidate_image
        )

        if candidate_features is None:
            continue

        is_exact_hash_match = are_exact_duplicates(query_image_path, image_path)
        similarity, signals = compute_multi_signal_similarity(
            query_features,
            candidate_features
        )

        cat = evidence.get("category", "Unknown")
        is_person = "person" in str(cat).lower() or "person" in str(image_path).lower()

        classification = classify_match(similarity, is_exact_hash_match=is_exact_hash_match, is_person=is_person)
        investigative_stat = investigative_status(similarity, is_exact_hash_match=is_exact_hash_match, is_person=is_person)
        action = recommended_action(similarity, is_exact_hash_match=is_exact_hash_match, is_person=is_person)
        ver_req = is_verification_required(similarity, is_exact_hash_match=is_exact_hash_match, is_person=is_person)

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

        results.append({
            "evidence_id": evidence_id,
            "category": cat,
            "image": image_path,
            "image_path": image_path,
            "visual_similarity_score": float(round(similarity, 4)),
            "similarity": float(round(similarity, 4)),
            "edge_similarity": signals.get("edge_similarity", float(round(similarity, 4))),
            "orb_similarity": signals.get("orb_similarity", float(round(similarity, 4))),
            "color_similarity": signals.get("color_similarity", float(round(similarity, 4))),
            "grayscale_similarity": signals.get("grayscale_similarity", float(round(similarity, 4))),
            "semantic_score": semantic_score(similarity),
            "similarity_level": similarity_level_safe(similarity),
            "classification": classification,
            "status": classification,
            "investigation_status": investigative_stat,
            "sha256_exact_duplicate": bool(is_exact_hash_match),
            "is_exact_hash_match": bool(is_exact_hash_match),
            "verification_required": bool(ver_req),
            "action": action,
            "reason": reason,
            "signals": signals
        })

    results.sort(
        key=lambda item: (-item["visual_similarity_score"], str(item["evidence_id"]))
    )

    return results[:top_k]


# ============================================================
# SAFE SIMILARITY LEVEL
# ============================================================

def similarity_level_safe(score):
    """
    Obtain readable similarity level without
    duplicating threshold logic.
    """

    from similarity import similarity_level

    return similarity_level(
        score
    )


# ============================================================
# RUN COMPLETE CBIR PIPELINE
# ============================================================

def run_pipeline(
    case_folder,
    query_file_name,
    top_k=5
):
    """
    Run complete standalone CBIR pipeline.

    Parameters
    ----------
    case_folder : str
        Folder containing evidence for one case.

    query_file_name : str
        Name of the evidence image to investigate.

    top_k : int
        Maximum number of matches.

    Returns
    -------
    dict
        Complete CBIR result.
    """

    # --------------------------------------------------------
    # Validate case folder
    # --------------------------------------------------------

    if not os.path.isdir(
        case_folder
    ):

        return {

            "status": "Error",

            "message":
                "Case folder does not exist.",

            "source_evidence":
                None,

            "matches": [],

            "relationships": []
        }

    # --------------------------------------------------------
    # Load case evidence dynamically
    # --------------------------------------------------------

    case_evidence = load_case_evidence(
        case_folder
    )

    if not case_evidence:

        return {

            "status": "No Evidence",

            "message":
                "No supported evidence images found.",

            "source_evidence":
                None,

            "matches": [],

            "relationships": []
        }

    # --------------------------------------------------------
    # Find query evidence dynamically
    # --------------------------------------------------------

    query_path = os.path.join(
        case_folder,
        query_file_name
    )

    if not is_valid_image_path(
        query_path
    ):

        return {

            "status": "Error",

            "message":
                "Query image was not found or is unsupported.",

            "source_evidence":
                query_file_name,

            "matches": [],

            "relationships": []
        }

    query_evidence = {

        "evidence_id":
            os.path.splitext(
                query_file_name
            )[0],

        "image_path":
            query_path,

        "category":
            os.path.basename(
                case_folder
            )
    }

    # --------------------------------------------------------
    # Search similar evidence
    # --------------------------------------------------------

    matches = search_case_evidence(
        query_evidence,
        case_evidence,
        top_k
    )

    # --------------------------------------------------------
    # Generate relationships
    # --------------------------------------------------------

    relationships = generate_relationships(
        query_evidence[
            "evidence_id"
        ],
        matches
    )

    # --------------------------------------------------------
    # Final result
    # --------------------------------------------------------

    return {

        "status":
            "Success",

        "source_evidence":
            query_evidence[
                "evidence_id"
            ],

        "case_folder":
            case_folder,

        "matches":
            matches,

        "relationships":
            relationships
    }


# ============================================================
# DISPLAY RESULTS
# ============================================================

def display_results(result):

    print()
    print("=" * 70)
    print("DIGITAL EVIDENCE EPRA")
    print("CBIR COMPLETE PIPELINE")
    print("=" * 70)

    print(
        f"\nStatus: {result['status']}"
    )

    if result.get("message"):
        print(
            f"Message: {result['message']}"
        )

    print(
        f"\nSource Evidence: "
        f"{result.get('source_evidence')}"
    )

    print("\n" + "-" * 70)
    print("SIMILAR EVIDENCE")
    print("-" * 70)

    matches = result.get(
        "matches",
        []
    )

    if not matches:
        print(
            "No similar evidence found."
        )
    else:
        for rank, match in enumerate(matches, start=1):
            if "rank" not in match:
                match["rank"] = rank
            if "query_evidence_id" not in match:
                match["query_evidence_id"] = result.get("source_evidence", "Query")
            print()
            print(render_investigator_image_card(match))

    print("\n" + "-" * 70)
    print("RELATIONSHIPS")
    print("-" * 70)

    relationships = result.get(
        "relationships",
        []
    )

    if not relationships:

        print(
            "No relationships generated."
        )

    else:

        for relationship in relationships:

            print(
                f"\n"
                f"{relationship['source_evidence']}"
                f"  -->  "
                f"{relationship['target_evidence']}"
            )

            print(
                f"Relationship : "
                f"{relationship['relationship']}"
            )

            print(
                f"Confidence   : "
                f"{relationship['confidence']:.2f}"
            )

            print(
                f"Action       : "
                f"{relationship['action']}"
            )

    print("\n" + "=" * 70)
    print("CBIR PIPELINE COMPLETED")
    print("=" * 70)


# ============================================================
# MAIN
# ============================================================

if __name__ == "__main__":

    print("=" * 70)
    print("DIGITAL EVIDENCE EPRA")
    print("STANDALONE CBIR PIPELINE")
    print("=" * 70)

    print(
        "\nEnter the path of the case evidence folder."
    )

    case_folder = input(
        "\nCase folder path: "
    ).strip()

    print(
        "\nEnter the exact image file name "
        "you want to investigate."
    )

    query_file_name = input(
        "\nQuery image name: "
    ).strip()

    result = run_pipeline(
        case_folder,
        query_file_name,
        top_k=5
    )

    display_results(
        result
    )

    # --------------------------------------------------------
    # Save complete result
    # --------------------------------------------------------

    output_file = os.path.join(
        case_folder,
        "cbir_result.json"
    )

    try:

        with open(
            output_file,
            "w",
            encoding="utf-8"
        ) as file:

            json.dump(
                result,
                file,
                indent=4
            )

        print(
            f"\nResult saved to:"
            f"\n{output_file}"
        )

    except Exception as error:

        print(
            f"\nUnable to save result: "
            f"{error}"
        )