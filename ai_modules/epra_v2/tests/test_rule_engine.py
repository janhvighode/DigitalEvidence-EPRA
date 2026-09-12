"""
Unit tests for RuleEngine.
"""

from ai_modules.epra_v2.adm.rule_engine import RuleEngine


def test_select_matrix_pdf():
    """
    PDF should return its ADM matrix.
    """
    matrix = RuleEngine.select_matrix("PDF")

    assert isinstance(matrix, dict)

    assert "AR" in matrix
    assert "CI" in matrix
    assert "BI" in matrix
    assert "SI" in matrix
    assert "II" in matrix


def test_select_matrix_email():
    """
    EMAIL should return its ADM matrix.
    """
    matrix = RuleEngine.select_matrix("EMAIL")

    assert isinstance(matrix, dict)

    assert "AR" in matrix
    assert "CI" in matrix
    assert "BI" in matrix
    assert "SI" in matrix
    assert "II" in matrix


def test_unknown_matrix():
    """
    Unknown evidence type should return UNKNOWN ADM.
    """
    unknown = RuleEngine.select_matrix("XYZ")
    default = RuleEngine.select_matrix("UNKNOWN")

    assert unknown == default


def test_case_insensitive():
    """
    Evidence type should be case insensitive.
    """
    upper = RuleEngine.select_matrix("PDF")
    lower = RuleEngine.select_matrix("pdf")

    assert upper == lower