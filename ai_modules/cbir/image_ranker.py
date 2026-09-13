# ======================================================
# Digital Evidence EPRA
# Module : CBIR
# File   : image_ranker.py
# Purpose: Rank retrieved evidence images.
# ======================================================

def similarity_level(score):
    """
    Convert similarity score into a readable level.
    """

    if score >= 0.90:
        return "Very High"

    elif score >= 0.75:
        return "High"

    elif score >= 0.60:
        return "Medium"

    elif score >= 0.40:
        return "Low"

    return "Very Low"


def duplicate_status(score):
    """
    Detect possible duplicate evidence.
    """

    if score >= 0.95:
        return "Duplicate"

    return "Match"


def rank_images(search_results, threshold=0.70):
    """
    Rank and filter CBIR search results.
    """

    ranked_results = []

    # Keep only relevant matches
    for result in search_results:

        if result["similarity"] >= threshold:

            result["level"] = similarity_level(
                result["similarity"]
            )

            result["status"] = duplicate_status(
                result["similarity"]
            )

            ranked_results.append(result)

    # Sort by similarity
    ranked_results.sort(
        key=lambda x: x["similarity"],
        reverse=True
    )

    # Add rank numbers
    for rank, result in enumerate(ranked_results, start=1):
        result["rank"] = rank

    return ranked_results