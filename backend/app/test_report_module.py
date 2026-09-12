import os
import sys
import tempfile
from pathlib import Path

# Configure isolated DB/storage BEFORE app import
_TEST_TMP = Path(tempfile.mkdtemp(prefix="report_test_"))
os.environ["EVIDENCE_DB_URL"] = f"sqlite:///{(_TEST_TMP / 'test_evidence.db').as_posix()}"
os.environ["EVIDENCE_STORAGE_DIR"] = str(_TEST_TMP / "uploads")

backend_dir = str(Path(__file__).resolve().parent.parent)
if backend_dir not in sys.path:
    sys.path.insert(0, backend_dir)

from app.database import SessionLocal, init_db
from app.schemas.report_schema import ReportRequest, ReportType
from app.services.report_service import ReportService
from app.services.backend_adapter import set_backend_adapter, MockBackendProvider, CaseData, EvidenceItem


def run_test():
    init_db()
    mock_provider = MockBackendProvider()
    set_backend_adapter(mock_provider)

    case_id = "CASE-2026-001"
    mock_provider.register_case(CaseData(
        case_id=case_id,
        case_title="Cyber Fraud Investigation",
        investigator_name="Deepak Sharma"
    ))
    mock_provider.register_evidence(EvidenceItem(
        evidence_id="EV-101",
        case_id=case_id,
        original_filename="fraud_doc.pdf",
        original_sha256="a3f5e8d9c7b2e4f1a6c9d3e8b7f5a2c4d8e9f7b6c5d4a3e2f1b0c9d8e7f6a5b4",
        verification_status="Verified"
    ))

    report = ReportRequest(
        case_id=case_id,
        case_title="Cyber Fraud Investigation",
        investigator_name="Deepak Sharma",
        report_type=ReportType.COMPREHENSIVE
    )

    db = SessionLocal()
    try:
        report_data = ReportService.assemble_report_data(report=report, db=db, is_draft=True)
        pdf = report_data["pdf_path"]

        print("=" * 60)
        print("REPORT MODULE TEST")
        print("=" * 60)
        print("Generated PDF :", pdf)

        # Assertions
        assert Path(pdf).exists(), "PDF report file must exist"
        assert Path(pdf).stat().st_size > 1000, "PDF must not be empty"
        assert Path(pdf).read_bytes()[:5] == b"%PDF-", "Generated file must have valid PDF header"
        assert "evidence_summary" in report_data
        assert "report_id" in report_data

        print("\n" + "=" * 60)
        print("REPORT MODULE TEST SUCCESS (ASSERTIONS PASSED)")
        print("=" * 60)
    finally:
        db.close()


if __name__ == "__main__":
    run_test()