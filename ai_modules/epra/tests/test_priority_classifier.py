from ai_modules.epra.ranking.priority_classifier import PriorityClassifier


def test_critical_priority():

    classifier = PriorityClassifier()

    priority = classifier.classify(0.95)

    assert priority == "CRITICAL"


def test_high_priority():

    classifier = PriorityClassifier()

    priority = classifier.classify(0.82)

    assert priority == "HIGH"


def test_medium_priority():

    classifier = PriorityClassifier()

    priority = classifier.classify(0.60)

    assert priority == "MEDIUM"


def test_low_priority():

    classifier = PriorityClassifier()

    priority = classifier.classify(0.30)

    assert priority == "LOW"