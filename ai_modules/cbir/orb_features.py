import cv2
import numpy as np


# ============================================================
# ORB CONFIGURATION
# ============================================================

ORB_MAX_FEATURES = 500
ORB_SCALE_FACTOR = 1.2
ORB_N_LEVELS = 8
ORB_EDGE_THRESHOLD = 31
ORB_PATCH_SIZE = 31


def create_orb_detector():
    """
    Create and return the ORB feature detector.

    ORB is used to identify local visual features such as
    corners, edges, and distinctive patterns.
    """

    orb = cv2.ORB_create(
        nfeatures=ORB_MAX_FEATURES,
        scaleFactor=ORB_SCALE_FACTOR,
        nlevels=ORB_N_LEVELS,
        edgeThreshold=ORB_EDGE_THRESHOLD,
        patchSize=ORB_PATCH_SIZE
    )

    return orb


def extract_orb_features(image):
    """
    Extract ORB keypoints and descriptors from an image.

    Parameters
    ----------
    image : numpy.ndarray
        Image loaded using OpenCV.

    Returns
    -------
    keypoints : list
        Detected ORB keypoints.

    descriptors : numpy.ndarray or None
        ORB descriptors.
    """

    if image is None:
        return [], None

    # --------------------------------------------------------
    # Convert image to grayscale
    # --------------------------------------------------------

    if len(image.shape) == 3:

        gray = cv2.cvtColor(
            image,
            cv2.COLOR_BGR2GRAY
        )

    else:

        gray = image

    # --------------------------------------------------------
    # Create ORB detector
    # --------------------------------------------------------

    orb = create_orb_detector()

    # --------------------------------------------------------
    # Detect keypoints and descriptors
    # --------------------------------------------------------

    keypoints, descriptors = orb.detectAndCompute(
        gray,
        None
    )

    return keypoints, descriptors


def get_orb_descriptor_count(descriptors):
    """
    Return the number of ORB descriptors detected.
    """

    if descriptors is None:
        return 0

    return int(len(descriptors))


def get_orb_feature_info(image):
    """
    Return useful information about ORB features.

    This is useful for testing and debugging.
    """

    keypoints, descriptors = extract_orb_features(
        image
    )

    return {
        "keypoints": len(keypoints),
        "descriptors": get_orb_descriptor_count(
            descriptors
        ),
        "descriptor_shape":
            None
            if descriptors is None
            else tuple(descriptors.shape)
    }


# ============================================================
# TEST
# ============================================================

if __name__ == "__main__":

    print("=" * 55)
    print("ORB FEATURE EXTRACTION TEST")
    print("=" * 55)

    print(
        f"Maximum ORB features : {ORB_MAX_FEATURES}"
    )

    print(
        f"Scale factor         : {ORB_SCALE_FACTOR}"
    )

    print(
        f"ORB levels           : {ORB_N_LEVELS}"
    )

    print(
        "\nORB module loaded successfully."
    )

    print(
        "Image-specific testing is handled by "
        "the CBIR pipeline."
    )

    print("=" * 55)