"""
Unit tests for SemanticAnalyzer.
"""

from ai_modules.epra_v2.intelligence.semantic_analyzer import SemanticAnalyzer


def test_semantic_upper_limit():

    assert SemanticAnalyzer.validate_score(1.5) == 1.0


def test_semantic_lower_limit():

    assert SemanticAnalyzer.validate_score(-1) == 0.0


def test_semantic_valid():

    assert SemanticAnalyzer.validate_score(0.72) == 0.72