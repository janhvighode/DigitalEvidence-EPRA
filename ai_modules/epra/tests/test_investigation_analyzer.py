from ai_modules.epra.intelligence.investigation_analyzer import InvestigationAnalyzer


def test_video_investigation():

    analyzer = InvestigationAnalyzer()

    assert analyzer.analyze("VIDEO") == 1.00


def test_pdf_investigation():

    analyzer = InvestigationAnalyzer()

    assert analyzer.analyze("PDF") == 0.80


def test_unknown_investigation():

    analyzer = InvestigationAnalyzer()

    assert analyzer.analyze("ABC") == 0.50