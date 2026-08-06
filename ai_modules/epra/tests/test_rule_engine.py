from ai_modules.epra.adm.rule_engine import RuleEngine


def test_image_rule():

    engine = RuleEngine()

    decision_path = engine.get_decision_path("IMAGE")

    assert decision_path == [
        "semantic",
        "authenticity",
        "context",
        "investigation",
        "behaviour"
    ]


def test_email_rule():

    engine = RuleEngine()

    decision_path = engine.get_decision_path("EMAIL")

    assert decision_path == [
        "behaviour",
        "semantic",
        "authenticity",
        "context",
        "investigation"
    ]


def test_unknown_rule():

    engine = RuleEngine()

    decision_path = engine.get_decision_path("UNKNOWN")

    assert decision_path == [
        "authenticity",
        "context",
        "semantic",
        "behaviour",
        "investigation"
    ]