from ai_modules.epra.ranking.evidence_ranker import EvidenceRanker


def test_evidence_ranking():

    ranker = EvidenceRanker()

    evidence = [
        {"id": 1, "score": 0.75},
        {"id": 2, "score": 0.95},
        {"id": 3, "score": 0.40},
        {"id": 4, "score": 0.82}
    ]

    ranked = ranker.rank(evidence)

    assert ranked[0]["id"] == 2
    assert ranked[1]["id"] == 4
    assert ranked[2]["id"] == 1
    assert ranked[3]["id"] == 3


def test_empty_list():

    ranker = EvidenceRanker()

    ranked = ranker.rank([])

    assert ranked == []


def test_single_evidence():

    ranker = EvidenceRanker()

    evidence = [
        {"id": 1, "score": 0.90}
    ]

    ranked = ranker.rank(evidence)

    assert ranked[0]["id"] == 1