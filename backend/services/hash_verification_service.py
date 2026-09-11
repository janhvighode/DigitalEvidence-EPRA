from datetime import datetime
from sqlalchemy.orm import Session

from models.case import Case
from models.evidence import Evidence
from models.evidence_hash import EvidenceHash
from services.integrity_service import IntegrityService


class HashVerificationService:

    @staticmethod
    def verify_evidence_integrity(
        original_hash: str | None,
        current_hash: str,
        verified_by_user_id: int | None = None
    ) -> dict:
        """
        Evaluates forensic integrity between original reference hash and
        current SHA-256 hash using Member 5 IntegrityService.

        Case 1: No reference hash provided
        -> status: "Unknown", hash_match: None, tampered: None

        Case 2: Matching hashes
        -> status: "Verified", hash_match: True, tampered: False

        Case 3: Altered hashes
        -> status: "Tampered", hash_match: False, tampered: True
        """
        clean_current = (current_hash or "").strip().lower()

        if not original_hash or not str(original_hash).strip():
            return {
                "original_hash": None,
                "current_hash": clean_current,
                "hash_match": None,
                "tampered": None,
                "integrity_status": "Unknown",
                "verification_date": None,
                "verified_by": None
            }

        clean_original = str(original_hash).strip().lower()

        # Call Member 5 IntegrityService
        verification = IntegrityService.verify_integrity(
            clean_original,
            clean_current
        )

        is_tampered = verification.get("tampered", True)
        is_verified = not is_tampered

        return {
            "original_hash": clean_original,
            "current_hash": clean_current,
            "hash_match": is_verified,
            "tampered": is_tampered,
            "integrity_status": "Verified" if is_verified else "Tampered",
            "verification_date": datetime.utcnow(),
            "verified_by": verified_by_user_id
        }

    @staticmethod
    def get_case_hash_summary(db: Session, case: Case) -> dict:
        """
        Calculates dynamic summary metrics for the CURRENT selected case only.
        Does NOT use global hardcoded or mock statistics.
        """
        evidence_hashes = (
            db.query(EvidenceHash)
            .join(Evidence, EvidenceHash.evidence_id == Evidence.id)
            .filter(Evidence.case_id == case.id)
            .all()
        )

        total_evidence = len(evidence_hashes)
        verified = sum(1 for h in evidence_hashes if h.integrity_status == "Verified")
        tampered = sum(1 for h in evidence_hashes if h.integrity_status == "Tampered")
        pending = sum(
            1 for h in evidence_hashes
            if h.integrity_status not in ["Verified", "Tampered"]
        )

        return {
            "case_id": case.case_id,
            "case_name": case.title,
            "status": case.status,
            "total_evidence": total_evidence,
            "verified": verified,
            "tampered": tampered,
            "pending": pending
        }
