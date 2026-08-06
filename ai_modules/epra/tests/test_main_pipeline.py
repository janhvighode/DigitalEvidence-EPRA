from ai_modules.epra.intelligence.factor_collector import FactorCollector


def test_factor_collector_pipeline():

    collector = FactorCollector()

    values = collector.collect("IMAGE")

    assert values["semantic"] == 0.90
    assert values["authenticity"] == 0.80
    assert values["context"] == 0.90
    assert values["investigation"] == 0.95
    assert values["behaviour"] == 0.60