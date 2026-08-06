from ai_modules.epra.intelligence.relationship_analyzer import RelationshipAnalyzer


def test_same_hash():

    analyzer = RelationshipAnalyzer()

    evidence1 = {
        "hash": "ABC123",
        "suspect_id": 1
    }

    evidence2 = {
        "hash": "ABC123",
        "suspect_id": 2
    }

    assert analyzer.are_related(evidence1, evidence2)


def test_same_suspect():

    analyzer = RelationshipAnalyzer()

    evidence1 = {
        "hash": "HASH1",
        "suspect_id": 5
    }

    evidence2 = {
        "hash": "HASH2",
        "suspect_id": 5
    }

    assert analyzer.are_related(evidence1, evidence2)


def test_not_related():

    analyzer = RelationshipAnalyzer()

    evidence1 = {
        "hash": "HASH1",
        "suspect_id": 1
    }

    evidence2 = {
        "hash": "HASH2",
        "suspect_id": 2
    }

    assert not analyzer.are_related(evidence1, evidence2)