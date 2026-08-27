from app.services.hash_service import HashService
from app.services.integrity_service import IntegrityService
from app.services.tamper_service import TamperService
from app.services.pdf_service import PDFService


class ReportService:

    @staticmethod
    def generate_report(report, timeline, activity):

        report_data = {

            "case_id": report.case_id,
            "case_title": report.case_title,
            "investigator_name": report.investigator_name,
            "suspect_name": report.suspect_name,
            "evidence_count": report.evidence_count,
            "timeline": timeline,
            "activity": activity

        }

        return report_data

    @staticmethod
    def verify_evidence(file_path, original_hash):

        current_hash = HashService.generate_sha256(file_path)

        integrity = IntegrityService.verify_integrity(
            original_hash,
            current_hash
        )

        tampering = TamperService.detect_tampering(
            original_hash,
            current_hash
        )

        return {

            "current_hash": current_hash,
            "integrity": integrity,
            "tampering": tampering

        }