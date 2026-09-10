# ======================================================
# Digital Evidence EPRA
# Module : CBIR
# File   : preprocessing.py
# Author : Member 3
# Purpose: Standardize evidence images before feature extraction.
# ======================================================

import cv2
import numpy as np


IMAGE_SIZE = (224, 224)


def load_image(image_path):
    """
    Load an image from disk.
    """

    image = cv2.imread(image_path)

    if image is None:
        print(f"Error: Unable to load image -> {image_path}")
        return None

    return image


def resize_image(image):
    """
    Resize image to standard dimensions.
    """

    return cv2.resize(image, IMAGE_SIZE)


def reduce_noise(image):
    """
    Remove small image noise.
    """

    return cv2.GaussianBlur(image, (5, 5), 0)


def normalize_image(image):
    """
    Normalize image brightness.
    """

    return cv2.normalize(image, None, 0, 255, cv2.NORM_MINMAX)


def preprocess_image(image_path):
    """
    Complete preprocessing pipeline.
    """

    image = load_image(image_path)

    if image is None:
        return None

    image = resize_image(image)

    image = reduce_noise(image)

    image = normalize_image(image)

    return image


# ------------------------------------------------------
# Testing
# ------------------------------------------------------

if __name__ == "__main__":

    test_image = "datasets/images/persons/person2.jpg"

    processed = preprocess_image(test_image)

    if processed is not None:

        cv2.imshow("Processed Image", processed)

        cv2.waitKey(0)

        cv2.destroyAllWindows()