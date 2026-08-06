"""
Unit tests for PriorityClassifier.
"""

from ai_modules.epra_v2.ranking.priority_classifier import PriorityClassifier


def test_critical():

    assert PriorityClassifier.classify(95) == "CRITICAL"


def test_high():

    assert PriorityClassifier.classify(82) == "HIGH"


def test_medium():

    assert PriorityClassifier.classify(65) == "MEDIUM"


def test_low():

    assert PriorityClassifier.classify(45) == "LOW"


def test_very_low():

    assert PriorityClassifier.classify(20) == "VERY LOW"