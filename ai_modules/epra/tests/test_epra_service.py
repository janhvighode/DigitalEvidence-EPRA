from pathlib import Path

from ai_modules.epra.services.epra_service import EPRAService


def test_epra_service():

    sample = Path("sample.txt")

    sample.write_text("EPRA Test")

    service = EPRAService()

    result = service.process(str(sample))

    assert "metadata" in result

    assert "evidence_type" in result

    assert "decision_path" in result

    assert "weights" in result

    assert "factor_values" in result

    assert "epra_score" in result

    assert "priority" in result

    sample.unlink()