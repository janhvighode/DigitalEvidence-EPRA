import os
import cv2
import numpy as np

from orb_features import extract_orb_features
from histogram_features import extract_color_histogram


# ============================================================
# DIGITAL EVIDENCE EPRA
# MODULE : CBIR
# FILE   : feature_extractor.py
# PURPOSE: Extract robust visual features from evidence images
# ============================================================

IMAGE_DATASET = "datasets/images"
FEATURE_FOLDER = "datasets/features"

IMAGE_SIZE = (224, 224)

ORB_MAX_KEYPOINTS = 300
ORB_DESCRIPTOR_SIZE = 32

SUPPORTED_EXTENSIONS = (
    ".jpg",
    ".jpeg",
    ".png",
    ".bmp",
    ".webp"
)


# ============================================================
# LOAD IMAGE
# ============================================================

def load_image(image_path):
    """
    Load an evidence image and resize it to the
    standard CBIR input size.
    """

    if not image_path:
        return None

    if not os.path.exists(image_path):
        print(f"Error: File does not exist -> {image_path}")
        return None

    image = cv2.imread(image_path)

    if image is None:
        print(f"Error: Unable to load image -> {image_path}")
        return None

    image = cv2.resize(
        image,
        IMAGE_SIZE,
        interpolation=cv2.INTER_AREA
    )

    return image


# ============================================================
# GRAYSCALE / STRUCTURAL FEATURES
# ============================================================

def extract_grayscale_features(image):
    """
    Extract normalized grayscale information.

    Used as a supporting visual feature rather than
    the only similarity source.
    """

    gray = cv2.cvtColor(
        image,
        cv2.COLOR_BGR2GRAY
    )

    gray = cv2.GaussianBlur(
        gray,
        (3, 3),
        0
    )

    features = gray.astype(
        np.float32
    ) / 255.0

    return features.flatten()


# ============================================================
# EDGE FEATURES
# ============================================================

def extract_edge_features(image):
    """
    Extract normalized edge information.

    Helps represent structural shape and boundaries.
    """

    gray = cv2.cvtColor(
        image,
        cv2.COLOR_BGR2GRAY
    )

    edges = cv2.Canny(
        gray,
        100,
        200
    )

    edges = edges.astype(
        np.float32
    ) / 255.0

    return edges.flatten()


# ============================================================
# ORB FIXED-SIZE FEATURES
# ============================================================

def extract_orb_features_fixed(image):
    """
    Extract ORB local features and convert them
    into a fixed-size vector.
    """

    _, descriptors = extract_orb_features(
        image
    )

    max_length = (
        ORB_MAX_KEYPOINTS *
        ORB_DESCRIPTOR_SIZE
    )

    if descriptors is None:
        return np.zeros(
            max_length,
            dtype=np.float32
        )

    descriptors = np.asarray(
        descriptors,
        dtype=np.float32
    )

    if descriptors.ndim != 2:
        return np.zeros(
            max_length,
            dtype=np.float32
        )

    # Limit number of descriptors
    descriptors = descriptors[
        :ORB_MAX_KEYPOINTS
    ]

    feature = descriptors.flatten()

    if len(feature) < max_length:

        feature = np.pad(
            feature,
            (0, max_length - len(feature))
        )

    elif len(feature) > max_length:

        feature = feature[
            :max_length
        ]

    feature /= 255.0

    return feature.astype(
        np.float32
    )


# ============================================================
# COLOR HISTOGRAM
# ============================================================

def extract_histogram_features(image):
    """
    Extract normalized color histogram features.
    """

    features = extract_color_histogram(
        image
    )

    if features is None:
        return np.zeros(
            512,
            dtype=np.float32
        )

    features = np.asarray(
        features,
        dtype=np.float32
    ).flatten()

    return features


# ============================================================
# NORMALIZE FEATURE BLOCK
# ============================================================

def normalize_feature_block(features):
    """
    Normalize one feature block using L2 normalization.
    """

    features = np.asarray(
        features,
        dtype=np.float32
    ).flatten()

    norm = np.linalg.norm(
        features
    )

    if norm == 0:
        return features

    return features / norm


# ============================================================
# FEATURE EXTRACTION
# ============================================================

def extract_features(image):
    """
    Extract multiple visual feature representations.

    Features:
        1. Grayscale structure
        2. Edge structure
        3. ORB local features
        4. Color histogram

    Every block is normalized independently before fusion.
    """

    if image is None:
        return None

    # Ensure standard size
    if (
        image.shape[1],
        image.shape[0]
    ) != IMAGE_SIZE:

        image = cv2.resize(
            image,
            IMAGE_SIZE,
            interpolation=cv2.INTER_AREA
        )

    # --------------------------------------------------------
    # Extract individual feature blocks
    # --------------------------------------------------------

    grayscale_features = (
        extract_grayscale_features(
            image
        )
    )

    edge_features = (
        extract_edge_features(
            image
        )
    )

    orb_features = (
        extract_orb_features_fixed(
            image
        )
    )

    histogram_features = (
        extract_histogram_features(
            image
        )
    )

    # --------------------------------------------------------
    # Normalize individual feature blocks
    # --------------------------------------------------------

    grayscale_features = (
        normalize_feature_block(
            grayscale_features
        )
    )

    edge_features = (
        normalize_feature_block(
            edge_features
        )
    )

    orb_features = (
        normalize_feature_block(
            orb_features
        )
    )

    histogram_features = (
        normalize_feature_block(
            histogram_features
        )
    )

    # --------------------------------------------------------
    # Feature fusion
    # --------------------------------------------------------

    combined_features = np.concatenate(
        [
            grayscale_features,
            edge_features,
            orb_features,
            histogram_features
        ]
    )

    combined_features = (
        combined_features.astype(
            np.float32
        )
    )

    return combined_features


# ============================================================
# GENERATE FEATURE PATH
# ============================================================

def generate_feature_path(
    image_path,
    feature_folder=FEATURE_FOLDER
):
    """
    Generate feature path.

    NOTE:
    Evidence IDs should eventually come from the backend/database.
    This filename-based ID is mainly for standalone testing.
    """

    category = os.path.basename(
        os.path.dirname(
            image_path
        )
    )

    filename = os.path.splitext(
        os.path.basename(
            image_path
        )
    )[0]

    filename = filename.replace(
        " ",
        "_"
    )

    evidence_id = (
        "EV_" +
        filename.upper()
    )

    category_folder = os.path.join(
        feature_folder,
        category
    )

    os.makedirs(
        category_folder,
        exist_ok=True
    )

    feature_path = os.path.join(
        category_folder,
        evidence_id + ".npy"
    )

    return (
        evidence_id,
        feature_path
    )


# ============================================================
# SAVE FEATURES
# ============================================================

def save_features(
    features,
    image_path,
    feature_folder=FEATURE_FOLDER
):
    """
    Save extracted feature vector.
    """

    if features is None:
        print(
            f"Error: No features generated -> {image_path}"
        )
        return None

    evidence_id, feature_path = (
        generate_feature_path(
            image_path,
            feature_folder
        )
    )

    np.save(
        feature_path,
        features
    )

    print(
        f"Evidence ID   : {evidence_id}"
    )

    print(
        f"Feature Shape : {features.shape}"
    )

    print(
        f"Saved Feature : {feature_path}"
    )

    return feature_path


# ============================================================
# PROCESS ONE IMAGE
# ============================================================

def process_image(
    image_path,
    feature_folder=FEATURE_FOLDER
):
    """
    Load → Extract → Save
    """

    image = load_image(
        image_path
    )

    if image is None:
        return None

    features = extract_features(
        image
    )

    return save_features(
        features,
        image_path,
        feature_folder
    )


# ============================================================
# PROCESS COMPLETE DATASET
# ============================================================

def process_dataset(
    image_dataset=IMAGE_DATASET,
    feature_folder=FEATURE_FOLDER
):
    """
    Process every supported image in the
    local testing dataset.
    """

    if not os.path.exists(
        image_dataset
    ):

        print(
            f"Error: Dataset folder not found -> "
            f"{image_dataset}"
        )

        return

    total_images = 0
    successful_images = 0

    print(
        "\n========================================"
    )

    print(
        "CBIR FEATURE EXTRACTION"
    )

    print(
        "========================================\n"
    )

    for category in sorted(
        os.listdir(
            image_dataset
        )
    ):

        category_path = os.path.join(
            image_dataset,
            category
        )

        if not os.path.isdir(
            category_path
        ):
            continue

        print(
            f"Processing Category: {category}"
        )

        for image_name in sorted(
            os.listdir(
                category_path
            )
        ):

            if not image_name.lower().endswith(
                SUPPORTED_EXTENSIONS
            ):
                continue

            total_images += 1

            image_path = os.path.join(
                category_path,
                image_name
            )

            result = process_image(
                image_path,
                feature_folder
            )

            if result is not None:
                successful_images += 1

        print()

    print(
        "========================================"
    )

    print(
        "FEATURE EXTRACTION COMPLETED"
    )

    print(
        "========================================"
    )

    print(
        f"Total Images : {total_images}"
    )

    print(
        f"Successful   : {successful_images}"
    )

    print(
        f"Failed       : "
        f"{total_images - successful_images}"
    )

    print(
        "========================================\n"
    )


# ============================================================
# VALIDATE FEATURE FILE
# ============================================================

def validate_feature_file(
    feature_path
):
    """
    Validate a saved .npy feature file.
    """

    if not feature_path:
        return False

    if not os.path.exists(
        feature_path
    ):

        print(
            f"Feature file not found -> "
            f"{feature_path}"
        )

        return False

    try:

        features = np.load(
            feature_path
        )

        print(
            f"Feature File : {feature_path}"
        )

        print(
            f"Shape        : {features.shape}"
        )

        print(
            f"Data Type    : {features.dtype}"
        )

        return True

    except Exception as error:

        print(
            "Unable to validate feature file:"
        )

        print(error)

        return False


# ============================================================
# MAIN
# ============================================================

if __name__ == "__main__":

    process_dataset()