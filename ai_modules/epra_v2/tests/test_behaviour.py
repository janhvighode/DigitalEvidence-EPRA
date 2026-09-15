"""
Unit tests for BehaviourAnalyzer.
"""

from ai_modules.epra_v2.intelligence.behaviour_analyzer import BehaviourAnalyzer


def test_behaviour_normalization():

    score = BehaviourAnalyzer.calculate_behaviour_intelligence(
        0.5,
        0.5,
        0.5,
        0.5
    )

    assert score == 0.5


def test_behaviour_maximum():

    score = BehaviourAnalyzer.calculate_behaviour_intelligence(
        1,
        1,
        1,
        1
    )

    assert score == 1.0


def test_behaviour_minimum():

    score = BehaviourAnalyzer.calculate_behaviour_intelligence(
        0,
        0,
        0,
        0
    )

    assert score == 0.0