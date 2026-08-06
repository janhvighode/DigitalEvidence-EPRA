from ai_modules.epra.intelligence.factor_collector import FactorCollector


def test_collect_returns_dictionary():

    collector = FactorCollector()

    values = collector.collect("IMAGE")

    assert isinstance(values, dict)

    assert len(values) == 5

    assert "semantic" in values

    assert "authenticity" in values

    assert "context" in values

    assert "investigation" in values

    assert "behaviour" in values