from ai_modules.epra.intelligence.evidence_classifier import EvidenceClassifier


def test_image_classification():

    classifier = EvidenceClassifier()

    result = classifier.classify("crime_photo.jpg")

    assert result == "IMAGE"



def test_executable_classification():

    classifier = EvidenceClassifier()

    result = classifier.classify("malware.exe")

    assert result == "EXECUTABLE"



def test_unknown_classification():

    classifier = EvidenceClassifier()

    result = classifier.classify("unknown.xyz")

    assert result == "UNKNOWN"