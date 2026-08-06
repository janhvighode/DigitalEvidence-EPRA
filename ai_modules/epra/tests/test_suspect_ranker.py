from ai_modules.epra.ranking.suspect_ranker import SuspectRanker


def test_suspect_score():

    ranker = SuspectRanker()

    evidence = [
        {
            "score": 0.95,
            "weight": 0.40
        },
        {
            "score": 0.82,
            "weight": 0.20
        },
        {
            "score": 0.75,
            "weight": 0.15
        },
        {
            "score": 0.91,
            "weight": 0.25
        }
    ]

    score = ranker.calculate_score(evidence)

    assert score == 0.884


def test_empty_evidence():

    ranker = SuspectRanker()

    score = ranker.calculate_score([])

    assert score == 0.0


def test_single_evidence():

    ranker = SuspectRanker()

    evidence = [
        {
            "score": 0.90,
            "weight": 1.00
        }
    ]

    score = ranker.calculate_score(evidence)

    assert score == 0.90