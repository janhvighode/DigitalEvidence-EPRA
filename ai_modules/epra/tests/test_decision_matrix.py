from ai_modules.epra.adm.decision_matrix import DecisionMatrix


def test_image_decision_matrix():

    matrix = DecisionMatrix()

    result = matrix.build("IMAGE")

    assert result["evidence_type"] == "IMAGE"

    assert result["decision_path"] == [
        "semantic",
        "authenticity",
        "context",
        "investigation",
        "behaviour"
    ]

    assert result["weights"]["semantic"] == 0.40
    assert result["weights"]["authenticity"] == 0.25
    assert result["weights"]["context"] == 0.15
    assert result["weights"]["investigation"] == 0.10
    assert result["weights"]["behaviour"] == 0.10


def test_email_decision_matrix():

    matrix = DecisionMatrix()

    result = matrix.build("EMAIL")

    assert result["evidence_type"] == "EMAIL"

    assert result["decision_path"][0] == "behaviour"

    assert result["weights"]["behaviour"] == 0.40


def test_unknown_decision_matrix():

    matrix = DecisionMatrix()

    result = matrix.build("UNKNOWN")

    assert result["evidence_type"] == "UNKNOWN"

    assert result["decision_path"][0] == "authenticity"