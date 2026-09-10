# ======================================================
# Digital Evidence EPRA
# Module : CBIR
# File   : metadata_matcher.py
# Author : Member 3
# Purpose: Compare evidence metadata.
# ======================================================

import os
import cv2


def extract_metadata(image_path):
    """
    Extract basic metadata from an evidence image.
    """

    image = cv2.imread(image_path)

    if image is None:
        return None

    height, width = image.shape[:2]

    metadata = {

        "filename": os.path.basename(image_path),

        "file_size": os.path.getsize(image_path),

        "width": width,

        "height": height,

        "extension": os.path.splitext(image_path)[1].lower()

    }

    return metadata


def compare_metadata(meta1, meta2):
    """
    Compare metadata of two evidence files.
    """

    score = 0

    if meta1["extension"] == meta2["extension"]:
        score += 25

    if meta1["width"] == meta2["width"]:
        score += 25

    if meta1["height"] == meta2["height"]:
        score += 25

    size_difference = abs(meta1["file_size"] - meta2["file_size"])

    if size_difference < 50000:
        score += 25

    return score / 100.0


# ------------------------------------------------------
# Testing
# ------------------------------------------------------

if __name__ == "__main__":

    image1 = "datasets/images/persons/person2.jpg"
    image2 = "datasets/images/persons/person2.jpg"

    meta1 = extract_metadata(image1)
    meta2 = extract_metadata(image2)

    similarity = compare_metadata(meta1, meta2)

    print("=" * 50)
    print("METADATA MATCHER")
    print("=" * 50)

    print(meta1)
    print()
    print(meta2)
    print()
    print(f"Metadata Similarity : {similarity:.2f}")