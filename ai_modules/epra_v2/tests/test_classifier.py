"""
Unit tests for EvidenceClassifier.
"""

from ai_modules.epra_v2.intelligence.evidence_classifier import EvidenceClassifier


def test_image_classification():
    assert EvidenceClassifier.classify("photo.jpg") == "IMAGE"


def test_video_classification():
    assert EvidenceClassifier.classify("movie.mp4") == "VIDEO"


def test_audio_classification():
    assert EvidenceClassifier.classify("song.mp3") == "AUDIO"


def test_pdf_classification():
    assert EvidenceClassifier.classify("report.pdf") == "PDF"


def test_document_classification():
    assert EvidenceClassifier.classify("notes.docx") == "DOCUMENT"


def test_spreadsheet_classification():
    assert EvidenceClassifier.classify("salary.xlsx") == "SPREADSHEET"


def test_email_classification():
    assert EvidenceClassifier.classify("mail.eml") == "EMAIL"


def test_executable_classification():
    assert EvidenceClassifier.classify("virus.exe") == "EXECUTABLE"


def test_database_classification():
    assert EvidenceClassifier.classify("records.db") == "DATABASE"


def test_log_classification():
    assert EvidenceClassifier.classify("system.log") == "LOG"


def test_archive_classification():
    assert EvidenceClassifier.classify("backup.zip") == "ARCHIVE"


def test_unknown_classification():
    assert EvidenceClassifier.classify("unknown.xyz") == "UNKNOWN"