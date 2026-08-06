from datetime import datetime, timedelta

from ai_modules.epra.intelligence.timeline_analyzer import TimelineAnalyzer


def test_recent_file():

    analyzer = TimelineAnalyzer()

    timestamp = (datetime.now() - timedelta(days=5)).isoformat()

    assert analyzer.is_recent(timestamp)


def test_old_file():

    analyzer = TimelineAnalyzer()

    timestamp = (datetime.now() - timedelta(days=100)).isoformat()

    assert not analyzer.is_recent(timestamp)


def test_age_calculation():

    analyzer = TimelineAnalyzer()

    timestamp = (datetime.now() - timedelta(days=20)).isoformat()

    age = analyzer.calculate_age(timestamp)

    assert age >= 20