"""
Unit tests for SemanticAnalyzer.
"""

from ai_modules.epra_v2.intelligence.semantic_analyzer import SemanticAnalyzer
from ai_modules.epra_v2.models.evidence import Evidence
from ai_modules.epra_v2.models.metadata import Metadata


def test_semantic_upper_limit():
    assert SemanticAnalyzer.validate_score(1.5) == 1.0


def test_semantic_lower_limit():
    assert SemanticAnalyzer.validate_score(-1) == 0.0


def test_semantic_valid():
    assert SemanticAnalyzer.validate_score(0.72) == 0.72


def test_image_consumes_member3_semantic_score_only():
    m = Metadata(file_name="photo.jpg", extension=".jpg", mime_type="image/jpeg", size=1000, absolute_path="")
    m.evidence_type = "IMAGE"
    e = Evidence(metadata=m, semantic_score=0.85)

    SemanticAnalyzer.process(e, demo_mode=False)
    assert e.semantic_intelligence == 0.85
    assert "SI" not in e.pending_external_inputs


def test_image_missing_member3_score_is_pending():
    m = Metadata(file_name="photo.jpg", extension=".jpg", mime_type="image/jpeg", size=1000, absolute_path="")
    m.evidence_type = "IMAGE"
    e = Evidence(metadata=m, semantic_score=0.0)

    SemanticAnalyzer.process(e, demo_mode=False)
    assert e.semantic_intelligence == 0.0
    assert "SI" in e.pending_external_inputs
    assert "Member 3" in e.pending_external_inputs["SI"]


def test_non_image_email_content_semantic_score():
    case_ctx = {
        "description": "Investigation into unauthorized wire transfers and phishing attack",
        "keywords": ["wire", "transfer", "phishing", "bank", "credentials"]
    }
    m = Metadata(
        file_name="urgent_transfer.eml",
        extension=".eml",
        mime_type="message/rfc822",
        size=500,
        absolute_path="",
        extracted_text="Subject: Urgent wire transfer request\nPlease verify bank credentials and authorize transfer."
    )
    m.evidence_type = "EMAIL"
    e = Evidence(metadata=m)

    SemanticAnalyzer.process(e, demo_mode=False, case_context=case_ctx)
    # Measured similarity > 0
    assert e.semantic_intelligence > 0.0
    assert 0.0 <= e.semantic_intelligence <= 1.0
    assert "SI" not in e.pending_external_inputs


def test_non_image_document_semantic_score():
    case_ctx = {
        "description": "Ransomware encryption incident",
        "keywords": ["ransom", "bitcoin", "decryptor", "payment"]
    }
    m = Metadata(
        file_name="instructions.txt",
        extension=".txt",
        mime_type="text/plain",
        size=300,
        absolute_path="",
        extracted_text="All your files are encrypted. Pay bitcoin to obtain the decryptor key."
    )
    m.evidence_type = "DOCUMENT"
    e = Evidence(metadata=m)

    SemanticAnalyzer.process(e, demo_mode=False, case_context=case_ctx)
    assert e.semantic_intelligence > 0.0
    assert 0.0 <= e.semantic_intelligence <= 1.0
    assert "SI" not in e.pending_external_inputs


def test_non_image_log_semantic_score():
    case_ctx = {
        "description": "Brute force login attack on SSH port",
        "keywords": ["failed", "password", "ssh", "invalid", "root"]
    }
    m = Metadata(
        file_name="auth.log",
        extension=".log",
        mime_type="text/plain",
        size=500,
        absolute_path="",
        extracted_text="Failed password for invalid user root from 198.51.100.2 port 22 ssh2"
    )
    m.evidence_type = "LOG"
    e = Evidence(metadata=m)

    SemanticAnalyzer.process(e, demo_mode=False, case_context=case_ctx)
    assert e.semantic_intelligence > 0.0
    assert 0.0 <= e.semantic_intelligence <= 1.0
    assert "SI" not in e.pending_external_inputs


def test_non_image_csv_spreadsheet_semantic_score():
    case_ctx = {
        "description": "Illicit cryptocurrency transactions",
        "keywords": ["crypto", "wallet", "ledger", "ethereum", "amount"]
    }
    m = Metadata(
        file_name="ledger.csv",
        extension=".csv",
        mime_type="text/csv",
        size=400,
        absolute_path="",
        extracted_text="TxID,Crypto,Wallet,Amount\n1,Ethereum,0x71c6,500.0"
    )
    m.evidence_type = "SPREADSHEET"
    e = Evidence(metadata=m)

    SemanticAnalyzer.process(e, demo_mode=False, case_context=case_ctx)
    assert e.semantic_intelligence > 0.0
    assert 0.0 <= e.semantic_intelligence <= 1.0
    assert "SI" not in e.pending_external_inputs


def test_non_image_missing_content_is_pending():
    case_ctx = {
        "description": "Financial fraud",
        "keywords": ["fraud", "bank"]
    }
    # Binary file with no extracted_text supplied
    m = Metadata(
        file_name="recording.wav",
        extension=".wav",
        mime_type="audio/wav",
        size=5000,
        absolute_path=""
    )
    m.evidence_type = "AUDIO"
    e = Evidence(metadata=m)

    SemanticAnalyzer.process(e, demo_mode=False, case_context=case_ctx)
    assert e.semantic_intelligence == 0.0
    assert "SI" in e.pending_external_inputs
    assert "NOT AVAILABLE / INTEGRATION PENDING" in e.pending_external_inputs["SI"]


def test_non_image_missing_case_context_is_pending():
    m = Metadata(
        file_name="statement.txt",
        extension=".txt",
        mime_type="text/plain",
        size=300,
        absolute_path="",
        extracted_text="Bank transaction statement wire credit 50000"
    )
    m.evidence_type = "DOCUMENT"
    e = Evidence(metadata=m)

    # case_context is None
    SemanticAnalyzer.process(e, demo_mode=False, case_context=None)
    assert e.semantic_intelligence == 0.0
    assert "SI" in e.pending_external_inputs
    assert "NOT AVAILABLE / INTEGRATION PENDING" in e.pending_external_inputs["SI"]


def test_no_filename_keyword_heuristics_in_production():
    # File named "phishing_wallet_credential.txt" but completely empty/unrelated content
    case_ctx = {
        "description": "phishing and stolen wallet credentials",
        "keywords": ["phishing", "wallet", "credential"]
    }
    m = Metadata(
        file_name="phishing_wallet_credential.txt",
        extension=".txt",
        mime_type="text/plain",
        size=100,
        absolute_path="",
        extracted_text="Unrelated cooking recipe with carrots and broccoli."
    )
    m.evidence_type = "DOCUMENT"
    e = Evidence(metadata=m)

    SemanticAnalyzer.process(e, demo_mode=False, case_context=case_ctx)
    # Measured similarity with zero lexical overlap: must NOT use filename keywords!
    assert e.semantic_intelligence == 0.0
    # Because content was analyzed against context, it is a MEASURED 0.0, not pending
    assert "SI" not in e.pending_external_inputs