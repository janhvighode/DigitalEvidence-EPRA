from ai_modules.epra.ranking.epra_engine import EPRAEngine


def test_epra_score():

    engine = EPRAEngine()

    factor_values = {
        "semantic": 0.90,
        "authenticity": 0.80,
        "context": 0.60,
        "investigation": 0.70,
        "behaviour": 0.30
    }

    weights = {
        "semantic": 0.40,
        "authenticity": 0.25,
        "context": 0.15,
        "investigation": 0.10,
        "behaviour": 0.10
    }

    score = engine.calculate_score(factor_values, weights)

    assert score == 0.75


def test_zero_score():

    engine = EPRAEngine()

    factor_values = {
        "semantic": 0.0,
        "authenticity": 0.0,
        "context": 0.0,
        "investigation": 0.0,
        "behaviour": 0.0
    }

    weights = {
        "semantic": 0.40,
        "authenticity": 0.25,
        "context": 0.15,
        "investigation": 0.10,
        "behaviour": 0.10
    }

    score = engine.calculate_score(factor_values, weights)

    assert score == 0.0


def test_full_score():

    engine = EPRAEngine()

    factor_values = {
        "semantic": 1.0,
        "authenticity": 1.0,
        "context": 1.0,
        "investigation": 1.0,
        "behaviour": 1.0
    }

    weights = {
        "semantic": 0.40,
        "authenticity": 0.25,
        "context": 0.15,
        "investigation": 0.10,
        "behaviour": 0.10
    }

    score = engine.calculate_score(factor_values, weights)

    assert score == 1.0