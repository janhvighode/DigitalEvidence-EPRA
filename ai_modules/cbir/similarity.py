# ============================================================
# Digital Evidence EPRA
# Module : CBIR
# File   : similarity.py
# Purpose: Calculate reliable visual similarity between evidence
#          images and classify the result conservatively.
# Author : Member 3 (Trisha)
# ============================================================

import os
import numpy as np

try:
    from sklearn.metrics.pairwise import cosine_similarity
except ImportError:
    def cosine_similarity(f1, f2):
        v1 = np.asarray(f1, dtype=np.float32)
        v2 = np.asarray(f2, dtype=np.float32)
        dot = np.dot(v1, v2.T)
        norm1 = np.linalg.norm(v1, axis=1, keepdims=True)
        norm2 = np.linalg.norm(v2, axis=1, keepdims=True)
        denom = norm1 * norm2.T
        denom[denom == 0] = 1e-12
        return dot / denom



# ============================================================
# CONFIGURATION
# ============================================================

COSINE_WEIGHT = 0.70
EUCLIDEAN_WEIGHT = 0.30

VERY_HIGH_THRESHOLD = 0.90
HIGH_THRESHOLD = 0.75
MEDIUM_THRESHOLD = 0.60
LOW_THRESHOLD = 0.40

# Duplicate thresholds
DUPLICATE_THRESHOLD = 0.98
NEAR_DUPLICATE_THRESHOLD = 0.93

# Conservative investigative thresholds
STRONG_MATCH_THRESHOLD = 0.85
POSSIBLE_MATCH_THRESHOLD = 0.75

# Minimum score required before calling an image
# visually similar.
VISUAL_RESEMBLANCE_THRESHOLD = 0.60


# ============================================================
# LOAD FEATURE VECTOR
# ============================================================

def load_feature_vector(feature_path):
    """
    Load a saved feature vector from a .npy file.

    Returns:
        numpy.ndarray or None
    """

    if not feature_path:
        return None

    if not os.path.exists(feature_path):
        print(
            f"Feature file not found -> {feature_path}"
        )
        return None

    try:
        features = np.load(feature_path)

        return np.asarray(
            features,
            dtype=np.float32
        ).flatten()

    except Exception as error:
        print(
            f"Error loading feature -> {feature_path}"
        )
        print(error)

        return None


# ============================================================
# VALIDATE FEATURE VECTORS
# ============================================================

def validate_features(feature1, feature2):
    """
    Validate two feature vectors before comparison.
    """

    if feature1 is None:
        return False

    if feature2 is None:
        return False

    try:
        feature1 = np.asarray(
            feature1,
            dtype=np.float32
        ).flatten()

        feature2 = np.asarray(
            feature2,
            dtype=np.float32
        ).flatten()

    except Exception:
        return False

    if feature1.size == 0:
        return False

    if feature2.size == 0:
        return False

    if feature1.shape != feature2.shape:
        print(
            "Warning: Feature dimension mismatch"
        )

        print(
            f"Feature 1 shape : {feature1.shape}"
        )

        print(
            f"Feature 2 shape : {feature2.shape}"
        )

        return False

    return True


# ============================================================
# COSINE SIMILARITY
# ============================================================

def cosine_similarity_score(feature1, feature2):
    """
    Calculate cosine similarity between two feature vectors.

    Returns:
        Float between 0 and 1.
    """

    if not validate_features(
        feature1,
        feature2
    ):
        return 0.0

    feature1 = np.asarray(
        feature1,
        dtype=np.float32
    ).reshape(1, -1)

    feature2 = np.asarray(
        feature2,
        dtype=np.float32
    ).reshape(1, -1)

    score = cosine_similarity(
        feature1,
        feature2
    )

    score = float(
        score[0][0]
    )

    return max(
        0.0,
        min(1.0, score)
    )


# ============================================================
# EUCLIDEAN SIMILARITY
# ============================================================

def euclidean_similarity_score(
    feature1,
    feature2
):
    """
    Convert Euclidean distance into a normalized
    similarity score.

    Returns:
        Float between 0 and 1.
    """

    if not validate_features(
        feature1,
        feature2
    ):
        return 0.0

    feature1 = np.asarray(
        feature1,
        dtype=np.float32
    )

    feature2 = np.asarray(
        feature2,
        dtype=np.float32
    )

    distance = np.linalg.norm(
        feature1 - feature2
    )

    similarity = 1.0 / (
        1.0 + float(distance)
    )

    return max(
        0.0,
        min(
            1.0,
            float(similarity)
        )
    )


# ============================================================
# COMBINED VISUAL SIMILARITY
# ============================================================

def calculate_similarity(
    feature1,
    feature2
):
    """
    Calculate the combined visual similarity.

    The score combines:

        70% cosine similarity
        30% Euclidean similarity

    IMPORTANT:
    This score represents visual similarity only.

    It does NOT prove:
        - same person
        - same object
        - same device
        - same crime
        - same source

    Returns:
        Float between 0 and 1.
    """

    if not validate_features(
        feature1,
        feature2
    ):
        return 0.0

    cosine = cosine_similarity_score(
        feature1,
        feature2
    )

    euclidean = euclidean_similarity_score(
        feature1,
        feature2
    )

    final_score = (
        COSINE_WEIGHT * cosine
        +
        EUCLIDEAN_WEIGHT * euclidean
    )

    final_score = max(
        0.0,
        min(
            1.0,
            final_score
        )
    )

    return float(
        round(
            final_score,
            4
        )
    )


# ============================================================
# SIMILARITY LEVEL
# ============================================================

def similarity_level(score):
    """
    Convert numerical visual similarity into
    a readable visual similarity level.
    """

    try:
        score = float(score)

    except (TypeError, ValueError):
        score = 0.0

    score = max(
        0.0,
        min(1.0, score)
    )

    if score >= VERY_HIGH_THRESHOLD:
        return "Very High"

    elif score >= HIGH_THRESHOLD:
        return "High"

    elif score >= MEDIUM_THRESHOLD:
        return "Medium"

    elif score >= LOW_THRESHOLD:
        return "Low"

    else:
        return "Very Low"


# ============================================================
# SEMANTIC SCORE
# ============================================================

def semantic_score(score):
    """
    Convert similarity into a clean score suitable
    for JSON/API communication.

    NOTE:
    This is a normalized visual similarity score.
    It is NOT proof of semantic identity.
    """

    try:
        score = float(score)

    except (TypeError, ValueError):
        score = 0.0

    score = max(
        0.0,
        min(1.0, score)
    )

    return float(
        round(
            score,
            2
        )
    )


# ============================================================
# VISUAL RESEMBLANCE CHECK
# ============================================================

def has_visual_resemblance(score):
    """
    Determine whether the images have meaningful
    visual resemblance.

    This is intentionally conservative.
    """

    try:
        score = float(score)

    except (TypeError, ValueError):
        return False

    return score >= VISUAL_RESEMBLANCE_THRESHOLD


# ============================================================
# MATCH CLASSIFICATION
# ============================================================

def classify_match(score):
    """
    Conservative evidence classification.

    IMPORTANT:
    A normal visual similarity score must NOT automatically
    be interpreted as a forensic relationship.

    High visual resemblance can occur because of:
        - similar background
        - similar lighting
        - similar colors
        - similar image composition
        - common object shapes

    Therefore only extremely high similarity is classified
    as duplicate/near-duplicate.

    Lower scores are classified as visual resemblance only.
    """

    try:
        score = float(score)

    except (TypeError, ValueError):
        score = 0.0

    score = max(
        0.0,
        min(1.0, score)
    )

    # Extremely high similarity
    if score >= DUPLICATE_THRESHOLD:
        return "Exact Duplicate"

    # Very strong visual similarity
    elif score >= NEAR_DUPLICATE_THRESHOLD:
        return "Near Duplicate"

    # Strong visual resemblance
    elif score >= STRONG_MATCH_THRESHOLD:
        return "Strong Visual Match"

    # Possible visual resemblance
    elif score >= POSSIBLE_MATCH_THRESHOLD:
        return "Possible Visual Resemblance"

    # Medium similarity can easily be caused by
    # common visual characteristics.
    elif score >= MEDIUM_THRESHOLD:
        return "Weak Visual Resemblance"

    else:
        return "No Significant Visual Match"


# ============================================================
# INVESTIGATIVE STATUS
# ============================================================

def investigative_status(score):
    """
    Convert visual similarity into a conservative
    investigation status.

    The CBIR module must not claim that two different
    people are the same person based only on image
    similarity.
    """

    try:
        score = float(score)

    except (TypeError, ValueError):
        score = 0.0

    score = max(
        0.0,
        min(1.0, score)
    )

    if score >= DUPLICATE_THRESHOLD:
        return "Duplicate Candidate"

    elif score >= NEAR_DUPLICATE_THRESHOLD:
        return "Near-Duplicate Candidate"

    elif score >= STRONG_MATCH_THRESHOLD:
        return "Strong Visual Candidate"

    elif score >= POSSIBLE_MATCH_THRESHOLD:
        return "Possible Visual Candidate"

    elif score >= MEDIUM_THRESHOLD:
        return "Visual Resemblance Only"

    else:
        return "No Significant Match"


# ============================================================
# RECOMMENDED ACTION
# ============================================================

def recommended_action(score):
    """
    Return a conservative investigation action.

    CBIR provides assistance to the investigator.
    It does not make the final forensic decision.
    """

    try:
        score = float(score)

    except (TypeError, ValueError):
        score = 0.0

    score = max(
        0.0,
        min(1.0, score)
    )

    if score >= DUPLICATE_THRESHOLD:
        return "Verify Duplicate Before Merging"

    elif score >= NEAR_DUPLICATE_THRESHOLD:
        return "Manual Verification Required"

    elif score >= STRONG_MATCH_THRESHOLD:
        return "Prioritize Investigator Review"

    elif score >= POSSIBLE_MATCH_THRESHOLD:
        return "Review as Visual Candidate"

    elif score >= MEDIUM_THRESHOLD:
        return "Record as Visual Resemblance Only"

    else:
        return "Do Not Treat as Investigative Match"


# ============================================================
# COMPLETE SIMILARITY RESULT
# ============================================================

def generate_similarity_result(
    feature1,
    feature2
):
    """
    Generate a complete conservative CBIR result.
    """

    score = calculate_similarity(
        feature1,
        feature2
    )

    return {

        "similarity":
            float(score),

        "semantic_score":
            semantic_score(score),

        "similarity_level":
            similarity_level(score),

        "visual_resemblance":
            has_visual_resemblance(score),

        "classification":
            classify_match(score),

        "investigative_status":
            investigative_status(score),

        "action":
            recommended_action(score)
    }


# ============================================================
# TEST
# ============================================================

if __name__ == "__main__":

    print("=" * 70)

    print(
        "DIGITAL EVIDENCE EPRA"
    )

    print(
        "CBIR SIMILARITY MODULE TEST"
    )

    print("=" * 70)

    test_scores = [
        1.00,
        0.97,
        0.94,
        0.87,
        0.78,
        0.65,
        0.45,
        0.20
    ]

    for score in test_scores:

        print()

        print(
            f"Similarity          : {score:.2f}"
        )

        print(
            f"Semantic Score      : "
            f"{semantic_score(score):.2f}"
        )

        print(
            f"Similarity Level    : "
            f"{similarity_level(score)}"
        )

        print(
            f"Visual Resemblance  : "
            f"{has_visual_resemblance(score)}"
        )

        print(
            f"Classification      : "
            f"{classify_match(score)}"
        )

        print(
            f"Investigative Status: "
            f"{investigative_status(score)}"
        )

        print(
            f"Recommended Action  : "
            f"{recommended_action(score)}"
        )

        print("-" * 70)

    print()

    print(
        "IMPORTANT:"
    )

    print(
        "CBIR visual similarity does not prove identity,"
    )

    print(
        "same person, same object, or same crime."
    )

    print(
        "Final forensic decisions require investigator"
    )

    print(
        "verification and supporting evidence."
    )

    print("=" * 70)