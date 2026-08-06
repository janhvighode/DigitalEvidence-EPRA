from ai_modules.epra.intelligence.context_analyzer import ContextAnalyzer


def test_image_context():

    analyzer = ContextAnalyzer()

    assert analyzer.analyze("IMAGE") == 0.90


def test_email_context():

    analyzer = ContextAnalyzer()

    assert analyzer.analyze("EMAIL") == 0.85


def test_unknown_context():

    analyzer = ContextAnalyzer()

    assert analyzer.analyze("XYZ") == 0.50