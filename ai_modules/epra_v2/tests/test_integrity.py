"""
Unit tests for IntegrityChecker.
"""

from ai_modules.epra_v2.intelligence.integrity_checker import IntegrityChecker


def test_hash_risk_match():

    assert IntegrityChecker.calculate_hash_risk(True) == 0.0


def test_hash_risk_mismatch():

    assert IntegrityChecker.calculate_hash_risk(False) == 1.0


def test_authenticity_risk():

    score = IntegrityChecker.calculate_authenticity_risk(
        1.0,
        0.5,
        0.5,
        0.0
    )

    assert score == 0.5


def test_verify_hash():

    h = "abcd1234"

    assert IntegrityChecker.verify_hash(h, h) is True


def test_verify_hash_fail():

    assert IntegrityChecker.verify_hash(
        "abc",
        "xyz"
    ) is False