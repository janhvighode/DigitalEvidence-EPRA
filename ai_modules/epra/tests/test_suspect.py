from ai_modules.epra.models.suspect import Suspect


def test_create_suspect():
    suspect = Suspect(
        suspect_id="S001",
        case_id="CASE001",
        name="John Doe"
    )

    assert suspect.suspect_id == "S001"
    assert suspect.name == "John Doe"
    assert suspect.confidence_score == 0.0