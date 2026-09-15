"""
Unit tests for RelationshipAnalyzer and Possible Suspect Detection.
"""

from ai_modules.epra_v2.intelligence.relationship_analyzer import RelationshipAnalyzer
from ai_modules.epra_v2.models.evidence import Evidence
from ai_modules.epra_v2.models.metadata import Metadata
from ai_modules.epra_v2.ranking.suspect_ranker import SuspectRanker


def test_email_entities_demo():
    metadata = Metadata(
        file_name="sample.pdf",
        extension=".pdf",
        mime_type="application/pdf",
        size=1024,
        absolute_path="C:/sample/sample.pdf",
        parent_directory="C:/sample"
    )
    metadata.evidence_type = "EMAIL"
    entities = RelationshipAnalyzer.extract_entities(metadata)
    assert len(entities) == 2


def test_unknown_entities_demo():
    metadata = Metadata(
        file_name="sample.pdf",
        extension=".pdf",
        mime_type="application/pdf",
        size=1024,
        absolute_path="C:/sample/sample.pdf",
        parent_directory="C:/sample"
    )
    metadata.evidence_type = "UNKNOWN"
    entities = RelationshipAnalyzer.extract_entities(metadata)
    assert entities == []


def test_extract_identifiers_from_text():
    text = """
    Contact attacker at root@darkweb.org or backup admin@c2server.com.
    Originating IP: 198.51.100.45.
    Local test IP 127.0.0.1 and 0.0.0.0 should be ignored.
    Pay Bitcoin to bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq or 1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa.
    Or ETH: 0x71C634C242b582572bA9736c0715367a14E53B29.
    Account: ACC-998811 and IBAN: IBAN-DE89370400440532013000.
    Transaction: TXN-554422 and INV-2026-001.
    """
    actor_pairs = RelationshipAnalyzer.extract_actor_identifiers(text)
    tx_ids = RelationshipAnalyzer.extract_transaction_identifiers(text)

    actor_types = [t for t, _ in actor_pairs]
    actor_values = [v for _, v in actor_pairs]

    # Verified actor extractions
    assert "root@darkweb.org" in actor_values
    assert "admin@c2server.com" in actor_values
    assert "198.51.100.45" in actor_values
    assert "127.0.0.1" not in actor_values
    assert "0.0.0.0" not in actor_values
    assert "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq" in actor_values
    assert "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa" in actor_values
    assert "0x71C634C242b582572bA9736c0715367a14E53B29" in actor_values
    assert any("ACC-998811" in v for v in actor_values)
    assert any("IBAN" in v for v in actor_values)

    # Transactions separated from suspects
    assert "TXN-554422" in tx_ids
    assert "INV-2026-001" in tx_ids
    assert "TXN-554422" not in actor_values


def test_type_aware_normalization():
    # Email: lowercase
    assert RelationshipAnalyzer.normalize_identifier("Alice@Target.COM ", "EMAIL") == "alice@target.com"
    # IPv4: canonical
    assert RelationshipAnalyzer.normalize_identifier("192.168.1.1", "IPV4") == "192.168.1.1"
    # Ethereum: lowercase for comparison
    eth = "0x71C634C242b582572bA9736c0715367a14E53B29"
    assert RelationshipAnalyzer.normalize_identifier(eth, "ETHEREUM") == eth.lower()
    # Bitcoin: preserve exact Base58 case
    btc = "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa"
    assert RelationshipAnalyzer.normalize_identifier(btc, "BITCOIN") == btc
    # Account: preserve case
    assert RelationshipAnalyzer.normalize_identifier("ACC-MainVault", "ACCOUNT") == "ACC-MainVault"


def test_single_identifier_in_single_evidence():
    m1 = Metadata(
        file_name="note.txt",
        extension=".txt",
        mime_type="text/plain",
        size=100,
        absolute_path="",
        evidence_id="EV-01",
        extracted_text="Found suspect email: attacker@protonmail.com"
    )
    e1 = Evidence(metadata=m1, epra_score=65.50)
    RelationshipAnalyzer.process(e1, demo_mode=False)

    assert "attacker@protonmail.com" in e1.related_entities

    suspects = RelationshipAnalyzer.generate_suspect_candidates([e1], demo_mode=False)
    ranked = SuspectRanker.rank(suspects)

    assert len(ranked) == 1
    assert ranked[0].suspect_name == "attacker@protonmail.com"
    assert ranked[0].total_epra_score == 65.50
    assert ranked[0].rank == 1
    assert ranked[0].linked_evidence_ids == ["EV-01"]


def test_same_identifier_across_multiple_evidence_deduplication():
    # Same attacker email in two evidence files with different EPRA scores
    m1 = Metadata(
        file_name="email1.eml",
        extension=".eml",
        mime_type="message/rfc822",
        size=200,
        absolute_path="",
        evidence_id="EV-01",
        extracted_text="Contact: badactor@darknet.io with ransom"
    )
    e1 = Evidence(metadata=m1, epra_score=50.00)
    RelationshipAnalyzer.process(e1, demo_mode=False)

    m2 = Metadata(
        file_name="ransom_note.txt",
        extension=".txt",
        mime_type="text/plain",
        size=150,
        absolute_path="",
        evidence_id="EV-02",
        extracted_text="Pay us, write to BadActor@Darknet.io immediately"
    )
    e2 = Evidence(metadata=m2, epra_score=35.25)
    RelationshipAnalyzer.process(e2, demo_mode=False)

    # Cross-evidence deduplication
    suspects = RelationshipAnalyzer.generate_suspect_candidates([e1, e2], demo_mode=False)
    ranked = SuspectRanker.rank(suspects)

    # Exactly 1 deduplicated suspect candidate
    assert len(ranked) == 1
    suspect = ranked[0]
    # Sum of linked evidence EPRA scores: 50.00 + 35.25 = 85.25
    assert suspect.total_epra_score == 85.25
    assert len(suspect.evidence_list) == 2
    assert set(suspect.linked_evidence_ids) == {"EV-01", "EV-02"}
    assert suspect.rank == 1


def test_multiple_distinct_identifiers_and_ranking():
    # Evidence 1: IP address (score 70)
    m1 = Metadata(file_name="c2.log", extension=".log", mime_type="text/plain", size=100, absolute_path="", evidence_id="EV-01", extracted_text="C2 at 198.51.100.99")
    e1 = Evidence(metadata=m1, epra_score=70.00)
    RelationshipAnalyzer.process(e1, demo_mode=False)

    # Evidence 2: Crypto wallet (score 90)
    m2 = Metadata(file_name="wallet.txt", extension=".txt", mime_type="text/plain", size=100, absolute_path="", evidence_id="EV-02", extracted_text="Send to 0x71C634C242b582572bA9736c0715367a14E53B29")
    e2 = Evidence(metadata=m2, epra_score=90.00)
    RelationshipAnalyzer.process(e2, demo_mode=False)

    suspects = RelationshipAnalyzer.generate_suspect_candidates([e1, e2], demo_mode=False)
    ranked = SuspectRanker.rank(suspects)

    assert len(ranked) == 2
    # Rank 1: crypto wallet (90.00)
    assert ranked[0].total_epra_score == 90.00
    assert ranked[0].rank == 1
    # Rank 2: IP address (70.00)
    assert ranked[1].total_epra_score == 70.00
    assert ranked[1].rank == 2


def test_alphabetical_tie_break():
    # Two suspects with identical total_epra_score (50.00)
    m1 = Metadata(file_name="f1.txt", extension=".txt", mime_type="text/plain", size=100, absolute_path="", evidence_id="EV-01", extracted_text="Contact bravo@test.com")
    e1 = Evidence(metadata=m1, epra_score=50.00)
    RelationshipAnalyzer.process(e1, demo_mode=False)

    m2 = Metadata(file_name="f2.txt", extension=".txt", mime_type="text/plain", size=100, absolute_path="", evidence_id="EV-02", extracted_text="Contact alpha@test.com")
    e2 = Evidence(metadata=m2, epra_score=50.00)
    RelationshipAnalyzer.process(e2, demo_mode=False)

    suspects = RelationshipAnalyzer.generate_suspect_candidates([e1, e2], demo_mode=False)
    ranked = SuspectRanker.rank(suspects)

    assert len(ranked) == 2
    assert ranked[0].total_epra_score == 50.00
    assert ranked[1].total_epra_score == 50.00
    # "alpha@test.com" comes before "bravo@test.com" alphabetically
    assert ranked[0].suspect_name.lower() < ranked[1].suspect_name.lower()
    assert ranked[0].suspect_name == "alpha@test.com"
    assert ranked[1].suspect_name == "bravo@test.com"


def test_no_identifier_yields_no_suspects():
    m1 = Metadata(
        file_name="clean.txt",
        extension=".txt",
        mime_type="text/plain",
        size=100,
        absolute_path="",
        evidence_id="EV-01",
        extracted_text="Standard operating procedure document with no actors or contacts."
    )
    e1 = Evidence(metadata=m1, epra_score=40.00)
    RelationshipAnalyzer.process(e1, demo_mode=False)

    assert e1.related_entities == []
    assert "RELATIONSHIP" in e1.pending_external_inputs

    suspects = RelationshipAnalyzer.generate_suspect_candidates([e1], demo_mode=False)
    assert suspects == []


def test_no_fake_human_names_in_production():
    m1 = Metadata(
        file_name="log.txt",
        extension=".txt",
        mime_type="text/plain",
        size=100,
        absolute_path="",
        evidence_id="EV-01",
        extracted_text="Inbound connection from 198.51.100.80"
    )
    e1 = Evidence(metadata=m1, epra_score=60.00)
    RelationshipAnalyzer.process(e1, demo_mode=False)

    suspects = RelationshipAnalyzer.generate_suspect_candidates([e1], demo_mode=False)
    assert len(suspects) == 1
    # Identity is the real extracted IP, never "Rahul", "Amit", or "Alice"
    assert suspects[0].suspect_name == "198.51.100.80"
    assert "Rahul" not in suspects[0].suspect_name
    assert "Amit" not in suspects[0].suspect_name