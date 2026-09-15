"""
Unit tests for ContextAnalyzer.
"""

from ai_modules.epra_v2.intelligence.context_analyzer import ContextAnalyzer


def test_context_returns_normalized_score():

    score = ContextAnalyzer.calculate_context_intelligence(
        "EMAIL",
        "fraud_transaction.eml"
    )

    assert 0.0 <= score <= 1.0


def test_context_keyword_priority():

    score = ContextAnalyzer.calculate_context_intelligence(
        "EMAIL",
        "bank_password_invoice.pdf"
    )

    assert score == 1.0