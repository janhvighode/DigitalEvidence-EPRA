from ai_modules.epra.adm.weight_generator import WeightGenerator


def test_image_weights():

    generator = WeightGenerator()

    decision_path = [
        "semantic",
        "authenticity",
        "context",
        "investigation",
        "behaviour"
    ]

    weights = generator.generate(decision_path)

    assert weights["semantic"] == 0.40
    assert weights["authenticity"] == 0.25
    assert weights["context"] == 0.15
    assert weights["investigation"] == 0.10
    assert weights["behaviour"] == 0.10


def test_email_weights():

    generator = WeightGenerator()

    decision_path = [
        "behaviour",
        "semantic",
        "authenticity",
        "context",
        "investigation"
    ]

    weights = generator.generate(decision_path)

    assert weights["behaviour"] == 0.40
    assert weights["semantic"] == 0.25
    assert weights["authenticity"] == 0.15
    assert weights["context"] == 0.10
    assert weights["investigation"] == 0.10