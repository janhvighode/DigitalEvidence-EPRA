# ======================================================
# Digital Evidence EPRA
# Module : CBIR
# File   : color_histogram.py
# Author : Member 3
# Purpose: Extract color histogram features from
#          evidence images.
# ======================================================

import cv2
import numpy as np


def extract_color_histogram(image):
    """
    Extract normalized color histogram from BGR image.
    """

    histogram = cv2.calcHist(
        [image],
        [0, 1, 2],
        None,
        [8, 8, 8],
        [0, 256, 0, 256, 0, 256]
    )

    histogram = cv2.normalize(histogram, histogram)

    return histogram.flatten()


# ------------------------------------------------------
# Testing
# ------------------------------------------------------

if __name__ == "__main__":

    image_path = "datasets/images/persons/person2.jpg"

    image = cv2.imread(image_path)

    if image is None:
        print("Image not found!")
        exit()

    histogram = extract_color_histogram(image)

    print("=" * 40)
    print("COLOR HISTOGRAM")
    print("=" * 40)

    print("Feature Vector Length :", len(histogram))

    print("\nFirst 20 Values:\n")

    print(histogram[:20])