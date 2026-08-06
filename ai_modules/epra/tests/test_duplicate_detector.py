from ai_modules.epra.intelligence.duplicate_detector import DuplicateDetector


def test_duplicate_hash():

    detector = DuplicateDetector()

    assert detector.is_duplicate(
        "ABC123",
        "ABC123"
    )


def test_different_hash():

    detector = DuplicateDetector()

    assert not detector.is_duplicate(
        "ABC123",
        "XYZ456"
    )


def test_find_duplicates():

    detector = DuplicateDetector()

    hashes = [
        "A",
        "B",
        "C",
        "A",
        "D",
        "B"
    ]

    duplicates = detector.find_duplicates(hashes)

    assert duplicates == [
        "A",
        "B"
    ]