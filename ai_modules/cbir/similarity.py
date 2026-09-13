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
    def cosine_similarity(a, b):
        a = np.asarray(a, dtype=np.float32)
        b = np.asarray(b, dtype=np.float32)
        norm_a = np.linalg.norm(a, axis=1, keepdims=True)
        norm_b = np.linalg.norm(b, axis=1, keepdims=True)
        denom = norm_a * norm_b.T
        denom[denom == 0] = 1e-9
        return np.dot(a, b.T) / denom



# ============================================================
# CONFIGURATION & FEATURE MODALITIES
# ============================================================

LEN_GRAY = 50176
LEN_EDGE = 50176
LEN_ORB = 9600
LEN_HIST = 512
TOTAL_FEATURE_LEN = LEN_GRAY + LEN_EDGE + LEN_ORB + LEN_HIST  # 110,464

# ------------------------------------------------------------
# TRANSPARENT HEURISTIC WEIGHTS
# NOTE: These weights are heuristic forensic parameters designed to
# prevent color/background bias from dominating visual matching.
# They are NOT a trained ML model and no scientific optimality or
# numerical accuracy percentage is claimed.
# Configurable constants:
# ------------------------------------------------------------
WEIGHT_EDGE = 0.35  # Edge / boundary structure agreement (heuristic)
WEIGHT_ORB = 0.25   # ORB keypoint / local pattern agreement (heuristic)
WEIGHT_HIST = 0.20  # Color distribution / histogram agreement (heuristic)
WEIGHT_GRAY = 0.20  # Grayscale intensity / luminance structure (heuristic)

# Forensic-safe classification thresholds
VERY_STRONG_MATCH_THRESHOLD = 0.93
NEAR_DUPLICATE_THRESHOLD = 0.93  # Alias for backward compatibility
STRONG_MATCH_THRESHOLD = 0.85
POSSIBLE_MATCH_THRESHOLD = 0.70
WEAK_MATCH_THRESHOLD = 0.50
VISUAL_RESEMBLANCE_THRESHOLD = 0.50

# Human-readable similarity level thresholds
VERY_HIGH_THRESHOLD = 0.90
HIGH_THRESHOLD = 0.75
MEDIUM_THRESHOLD = 0.60
LOW_THRESHOLD = 0.40


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
        f1 = np.asarray(feature1)
        f2 = np.asarray(feature2)

        if f1.size == 0 or f2.size == 0:
            return False

        return True

    except Exception:
        return False


# ============================================================
# COSINE SIMILARITY
# ============================================================

def cosine_similarity_score(
    feature1,
    feature2
):
    """
    Calculate normalized cosine similarity.

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
# FEATURE DECOMPOSITION & MULTI-SIGNAL SIMILARITY
# ============================================================

def decompose_features(features):
    """
    Decompose a combined 110,464-dimensional feature vector into its
    constituent visual modalities:
      1. Grayscale structure (50,176)
      2. Canny edge structure (50,176)
      3. ORB local descriptors (9,600)
      4. Color histogram (512)
    """
    if features is None:
        return None
    try:
        f = np.asarray(features, dtype=np.float32).flatten()
    except Exception:
        return None
    if len(f) != TOTAL_FEATURE_LEN:
        return None
    gray = f[0:LEN_GRAY]
    edge = f[LEN_GRAY:LEN_GRAY + LEN_EDGE]
    orb = f[LEN_GRAY + LEN_EDGE:LEN_GRAY + LEN_EDGE + LEN_ORB]
    hist = f[LEN_GRAY + LEN_EDGE + LEN_ORB:TOTAL_FEATURE_LEN]
    return gray, edge, orb, hist


def compute_multi_signal_similarity(feature1, feature2):
    """
    Calculate visual similarity across multiple visual modalities with
    conservative forensic guardrails to prevent false positives.

    Formula:
      visual_similarity_score = 0.35 * edge_similarity + 0.25 * orb_similarity
                              + 0.20 * color_similarity + 0.20 * grayscale_similarity

    Weights are transparent heuristic parameters (Edge 35%, ORB 25%, Color 20%, Grayscale 20%).
    No numerical accuracy percentage or scientific optimality is claimed.

    Guardrails:
      - Color/background similarity MUST NOT dominate.
      - Edge + ORB structural/local feature agreement is required.
      - If structural/local agreement is weak, score is downgraded to prevent
        unjustified 'Very Strong Visual Match' or 'Strong Visual Match'.
    """
    d1 = decompose_features(feature1)
    d2 = decompose_features(feature2)

    if not d1 or not d2:
        cos = cosine_similarity_score(feature1, feature2)
        euc = euclidean_similarity_score(feature1, feature2)
        score = max(0.0, min(1.0, float(0.70 * cos + 0.30 * euc)))
        return round(score, 4), {
            "edge_similarity": round(cos, 4),
            "orb_similarity": round(cos, 4),
            "color_similarity": round(cos, 4),
            "grayscale_similarity": round(cos, 4),
            "base_score": round(score, 4),
            "final_score": round(score, 4),
            "safeguard_applied": False
        }

    g1, e1, o1, h1 = d1
    g2, e2, o2, h2 = d2

    sim_edge = cosine_similarity_score(e1, e2)
    sim_orb = cosine_similarity_score(o1, o2)
    sim_hist = cosine_similarity_score(h1, h2)
    sim_gray = cosine_similarity_score(g1, g2)

    # Weighted multi-signal fusion (heuristic weights)
    base_score = (
        WEIGHT_EDGE * sim_edge +
        WEIGHT_ORB * sim_orb +
        WEIGHT_HIST * sim_hist +
        WEIGHT_GRAY * sim_gray
    )
    base_score = max(0.0, min(1.0, float(base_score)))

    final_score = base_score
    safeguard_applied = False

    # False-positive reduction guardrails:
    # Require structural (edge) and local (ORB) feature agreement so background/clothing
    # color cannot falsely produce a strong match between different entities.
    structural_local_agreement = 0.60 * sim_edge + 0.40 * sim_orb

    if structural_local_agreement < 0.25 or sim_edge < 0.20:
        final_score = min(final_score, 0.45)
        safeguard_applied = True
    elif structural_local_agreement < 0.40 or sim_edge < 0.35:
        final_score = min(final_score, 0.65)
        safeguard_applied = True
    elif structural_local_agreement < 0.50 or sim_edge < 0.45:
        # Cannot be Strong or Very Strong Match if structural agreement < 0.50
        final_score = min(final_score, 0.80)
        safeguard_applied = True
    elif structural_local_agreement < 0.70 or sim_edge < 0.60:
        # Cannot be Very Strong Match if structural agreement < 0.70
        final_score = min(final_score, 0.90)
        safeguard_applied = True

    final_score = float(round(max(0.0, min(1.0, final_score)), 4))

    signals = {
        "edge_similarity": float(round(sim_edge, 4)),
        "orb_similarity": float(round(sim_orb, 4)),
        "color_similarity": float(round(sim_hist, 4)),
        "grayscale_similarity": float(round(sim_gray, 4)),
        "hist_similarity": float(round(sim_hist, 4)),
        "gray_similarity": float(round(sim_gray, 4)),
        "structural_local_agreement": float(round(structural_local_agreement, 4)),
        "base_score": float(round(base_score, 4)),
        "final_score": final_score,
        "safeguard_applied": safeguard_applied
    }

    return final_score, signals


def calculate_similarity(feature1, feature2):
    """
    Calculate the combined visual similarity using multi-signal fusion.

    IMPORTANT:
    This score represents visual similarity only.
    It does NOT prove:
        - same person
        - same object
        - same device
        - same crime
        - same source

    Returns:
        Float between 0.0 and 1.0.
    """
    score, _ = compute_multi_signal_similarity(feature1, feature2)
    return score


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

def is_verification_required(score, is_exact_hash_match=False, is_person=False):
    """
    Indicate whether manual investigator verification is required.

    FORENSIC PRINCIPLES:
    - Exact cryptographic duplicates (SHA-256 match bit-for-bit) have verification_required=False
      (file identity verified cryptographically).
    - Actual visual matches/resemblances (score >= WEAK_MATCH_THRESHOLD) have verification_required=True.
    - No Significant Visual Match (score < WEAK_MATCH_THRESHOLD) has verification_required=False.
    """
    if is_exact_hash_match:
        return False
    try:
        score = float(score)
    except (TypeError, ValueError):
        score = 0.0
    if score < WEAK_MATCH_THRESHOLD:
        return False
    return True


def classify_match(score, is_exact_hash_match=False, is_person=False):
    """
    Forensic evidence duplicate and similarity classification.

    Hierarchy:
      1. Exact Duplicate (ONLY when SHA-256 matches bit-for-bit)
      2. Very Strong Visual Match (score >= 0.93)
      3. Strong Visual Match (score >= 0.85)
      4. Possible Visual Resemblance (score >= 0.70)
      5. Weak Visual Resemblance (score >= 0.50)
      6. No Significant Visual Match (score < 0.50)

    CRITICAL RULES:
    - 'Exact Duplicate' requires cryptographic SHA-256 equality bit-for-bit.
    - Visual similarity alone NEVER produces 'Exact Duplicate'.
    - Person images never output identity confirmations.
    """
    if is_exact_hash_match:
        return "Exact Duplicate"

    try:
        score = float(score)
    except (TypeError, ValueError):
        score = 0.0

    score = max(0.0, min(1.0, score))

    if score >= VERY_STRONG_MATCH_THRESHOLD:
        return "Very Strong Visual Match"
    elif score >= STRONG_MATCH_THRESHOLD:
        return "Strong Visual Match"
    elif score >= POSSIBLE_MATCH_THRESHOLD:
        return "Possible Visual Resemblance"
    elif score >= WEAK_MATCH_THRESHOLD:
        return "Weak Visual Resemblance"
    else:
        return "No Significant Visual Match"


# ============================================================
# INVESTIGATIVE STATUS
# ============================================================

def investigative_status(score, is_exact_hash_match=False, is_person=False):
    """
    Convert visual similarity into a standardized investigation status:
      - 'Exact Duplicate' (ONLY for SHA-256 exact match)
      - 'Candidate'
      - 'Possible Relationship'
      - 'Requires Verification'
      - 'No Significant Match'
    """
    if is_exact_hash_match:
        return "Exact Duplicate"

    try:
        score = float(score)
    except (TypeError, ValueError):
        score = 0.0

    score = max(0.0, min(1.0, score))

    if score >= STRONG_MATCH_THRESHOLD:
        return "Candidate"
    elif score >= POSSIBLE_MATCH_THRESHOLD:
        return "Possible Relationship"
    elif score >= WEAK_MATCH_THRESHOLD:
        return "Requires Verification"
    else:
        return "No Significant Match"


# ============================================================
# RECOMMENDED ACTION & FORENSIC REASONING
# ============================================================

def recommended_action(score, is_exact_hash_match=False, is_person=False):
    """
    Return a conservative forensic recommendation.
    Never claims 'same person confirmed'.
    """
    if is_exact_hash_match:
        return "Cryptographic SHA-256 duplicate verified bit-for-bit; review before record merge."

    try:
        score = float(score)
    except (TypeError, ValueError):
        score = 0.0

    score = max(0.0, min(1.0, score))

    if is_person:
        if score >= VERY_STRONG_MATCH_THRESHOLD:
            return "Very strong visual resemblance candidate. Does NOT confirm person identity. Formal facial/biometric verification required."
        elif score >= STRONG_MATCH_THRESHOLD:
            return "Strong visual resemblance candidate. Does NOT confirm person identity. Formal facial/biometric verification required."
        elif score >= POSSIBLE_MATCH_THRESHOLD:
            return "Possible visual resemblance candidate. Does NOT confirm identity. Requires investigator verification and supporting evidence."
        elif score >= WEAK_MATCH_THRESHOLD:
            return "Weak visual resemblance. Review supporting contextual evidence; verification required."
        else:
            return "No significant visual match found."

    if score >= VERY_STRONG_MATCH_THRESHOLD:
        return "Very strong visual resemblance candidate. Forensic verification required before evidentiary conclusion."
    elif score >= STRONG_MATCH_THRESHOLD:
        return "Strong visual candidate. Prioritize manual investigator review."
    elif score >= POSSIBLE_MATCH_THRESHOLD:
        return "Possible visual resemblance candidate. Review supporting contextual evidence."
    elif score >= WEAK_MATCH_THRESHOLD:
        return "Weak visual resemblance. Record as visual candidate requiring verification."
    else:
        return "No significant visual match. Do not treat as investigative match."


# ============================================================
# CONFIDENCE LEVEL & INVESTIGATION RECOMMENDATIONS
# ============================================================

def compute_confidence_level(score, is_exact_hash_match=False):
    """
    Derive investigator-friendly confidence level:
      - 'High'
      - 'Medium'
      - 'Low'

    Transparently derived from actual implemented evidence strength.
    Not a scientifically validated probability.
    """
    if is_exact_hash_match:
        return "High"

    try:
        score = float(score)
    except (TypeError, ValueError):
        score = 0.0

    score = max(0.0, min(1.0, score))

    if score >= STRONG_MATCH_THRESHOLD:  # 0.85
        return "High"
    elif score >= POSSIBLE_MATCH_THRESHOLD:  # 0.70
        return "Medium"
    else:
        return "Low"


def compute_investigation_recommendation(classification=None, score=None, is_exact_hash_match=False):
    """
    Derive conservative investigation recommendation:
      - 'KEEP_FOR_INVESTIGATION'
      - 'REVIEW_MANUALLY'
      - 'LOW_PRIORITY'
      - 'NOT_RECOMMENDED'

    Investigator decision support only. Never automatically discards evidence.
    """
    if is_exact_hash_match:
        return "KEEP_FOR_INVESTIGATION"

    if classification:
        c = str(classification)
        if "Exact Duplicate" in c or "Very Strong" in c:
            return "KEEP_FOR_INVESTIGATION"
        elif "Strong Visual Match" in c:
            return "KEEP_FOR_INVESTIGATION"
        elif "Possible Visual Resemblance" in c:
            return "REVIEW_MANUALLY"
        elif "Weak Visual Resemblance" in c:
            return "LOW_PRIORITY"
        elif "No Significant" in c:
            return "NOT_RECOMMENDED"

    if score is not None:
        try:
            score = float(score)
        except (TypeError, ValueError):
            score = 0.0
        score = max(0.0, min(1.0, score))
        if score >= STRONG_MATCH_THRESHOLD:
            return "KEEP_FOR_INVESTIGATION"
        elif score >= POSSIBLE_MATCH_THRESHOLD:
            return "REVIEW_MANUALLY"
        elif score >= WEAK_MATCH_THRESHOLD:
            return "LOW_PRIORITY"
        else:
            return "NOT_RECOMMENDED"

    return "NOT_RECOMMENDED"


# ============================================================
# COMPLETE SIMILARITY RESULT
# ============================================================

def generate_similarity_result(
    feature1,
    feature2,
    is_exact_hash_match=False,
    is_person=False
):
    """
    Generate a complete forensic CBIR result with multi-signal breakdown.
    """
    score, signals = compute_multi_signal_similarity(feature1, feature2)

    classification = classify_match(score, is_exact_hash_match=is_exact_hash_match, is_person=is_person)
    status = investigative_status(score, is_exact_hash_match=is_exact_hash_match, is_person=is_person)
    action = recommended_action(score, is_exact_hash_match=is_exact_hash_match, is_person=is_person)
    ver_req = is_verification_required(score, is_exact_hash_match=is_exact_hash_match, is_person=is_person)
    conf_level = compute_confidence_level(score, is_exact_hash_match=is_exact_hash_match)
    inv_rec = compute_investigation_recommendation(classification=classification, score=score, is_exact_hash_match=is_exact_hash_match)

    if is_exact_hash_match:
        reason = "SHA-256 hashes are identical; files are exact bit-for-bit duplicates."
    elif is_person and score >= VERY_STRONG_MATCH_THRESHOLD:
        reason = f"Very strong visual resemblance candidate (score {score:.4f}). Visual evidence only; does NOT confirm identity; verification required."
    elif is_person and score >= STRONG_MATCH_THRESHOLD:
        reason = f"Strong visual resemblance candidate (score {score:.4f}). Visual evidence only; does NOT confirm identity; verification required."
    elif is_person and score >= VISUAL_RESEMBLANCE_THRESHOLD:
        reason = f"Possible visual resemblance candidate (score {score:.4f}). Visual evidence only; does NOT confirm identity; verification required."
    elif score >= VERY_STRONG_MATCH_THRESHOLD:
        reason = f"Very strong visual candidate (score {score:.4f}). Verification required."
    elif score >= STRONG_MATCH_THRESHOLD:
        reason = f"Strong visual candidate (score {score:.4f}) supported by multi-signal agreement. Verification required."
    elif score >= POSSIBLE_MATCH_THRESHOLD:
        reason = f"Possible visual resemblance (score {score:.4f}). Verification required."
    elif score >= WEAK_MATCH_THRESHOLD:
        reason = f"Weak visual resemblance (score {score:.4f}). Verification required."
    else:
        reason = "No significant visual match found."

    return {
        "visual_similarity_score": float(score),
        "similarity": float(score),
        "edge_similarity": signals.get("edge_similarity", float(score)),
        "orb_similarity": signals.get("orb_similarity", float(score)),
        "color_similarity": signals.get("color_similarity", float(score)),
        "grayscale_similarity": signals.get("grayscale_similarity", float(score)),
        "semantic_score": semantic_score(score),
        "similarity_level": similarity_level(score),
        "visual_resemblance": has_visual_resemblance(score),
        "classification": classification,
        "confidence_level": conf_level,
        "investigation_recommendation": inv_rec,
        "sha256_exact_duplicate": bool(is_exact_hash_match),
        "is_exact_hash_match": bool(is_exact_hash_match),
        "verification_required": bool(ver_req),
        "investigation_status": status,
        "action": action,
        "reason": reason,
        "signals": signals
    }


# ============================================================
# TEST
# ============================================================

if __name__ == "__main__":

    print("=" * 70)
    print("DIGITAL EVIDENCE EPRA")
    print("CBIR SIMILARITY MODULE TEST")
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
        print(f"Similarity          : {score:.2f}")
        print(f"Semantic Score      : {semantic_score(score):.2f}")
        print(f"Similarity Level    : {similarity_level(score)}")
        print(f"Visual Resemblance  : {has_visual_resemblance(score)}")
        print(f"Classification      : {classify_match(score)}")
        print(f"Investigative Status: {investigative_status(score)}")
        print(f"Recommended Action  : {recommended_action(score)}")
        print("-" * 70)

    print()
    print("IMPORTANT:")
    print("CBIR visual similarity does not prove identity,")
    print("same person, same object, or same crime.")
    print("Final forensic decisions require investigator")
    print("verification and supporting evidence.")
    print("=" * 70)