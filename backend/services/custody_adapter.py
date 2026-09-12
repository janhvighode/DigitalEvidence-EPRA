from typing import Optional, List, Dict, Any
from datetime import datetime, timezone
from sqlalchemy.orm import Session

from models.case import Case
from models.evidence import Evidence
from models.evidence_record import EvidenceRecord
from models.evidence_hash import EvidenceHash
from models.user import User
from models.custody_log import CustodyLog
from services.custody_service import CustodyService


class CustodyAdapter:
    """
    Thin integration adapter connecting Deepak's Chain of Custody module
    to our existing Case, Evidence, EvidenceRecord, EvidenceHash, and User models.
    """

    @staticmethod
    def sync_authentic_evidence_events(db: Session, case_id: int, current_user: Optional[User] = None):
        """
        Idempotently synchronizes authentic evidence events (Upload and Hash Verification)
        from our existing database records into CustodyLog.
        Guarantees zero duplicate entries via deterministic external_event_id keys.
        Never recalculates SHA-256 hashes.
        """
        str_case_id = str(case_id)

        # 1. Fetch real evidence items for this case
        evidences = db.query(Evidence).filter(Evidence.case_id == case_id).all()
        for ev in evidences:
            ev_id_str = ev.evidence_id or str(ev.id)
            
            # Ensure CurrentCustodyInfo exists with authentic defaults
            CustodyService.get_or_create_current_custody(db, ev_id_str, str_case_id)

            # Idempotently record UPLOAD event if not already present
            upload_event_id = f"EV_UPLOAD_{ev.id}"
            existing_upload = db.query(CustodyLog).filter(
                CustodyLog.external_event_id == upload_event_id
            ).first()

            if not existing_upload:
                actor_name = current_user.full_name or current_user.username if current_user else "Investigator"
                actor_id = str(current_user.id) if current_user else None
                actor_role = "Cyber Expert" if (current_user and current_user.role_id == 3) else ("Investigator" if (current_user and current_user.role_id == 2) else "Administrator")
                
                upload_time = ev.created_at or datetime.now(timezone.utc)
                if upload_time.tzinfo is None:
                    upload_time = upload_time.replace(tzinfo=timezone.utc)

                CustodyService.create_log(
                    db=db,
                    evidence_id=ev_id_str,
                    case_id=str_case_id,
                    external_event_id=upload_event_id,
                    investigator_id=actor_id,
                    investigator_name=actor_name,
                    actor_role=actor_role,
                    action="EVIDENCE_UPLOADED",
                    event_type="UPLOAD",
                    title="Uploaded to DEPS",
                    result="SUCCESS",
                    remarks=f"Evidence file '{ev.file_name}' ({ev.file_type}, {ev.file_size} bytes) ingested into system repository.",
                    source_reference="DEPS_STORAGE",
                    is_system_action=False,
                    actor_is_unverified=False,
                    timestamp=upload_time
                )

            # 2. Check for authentic SHA-256 Hash records in EvidenceHash (DO NOT recalculate)
            hash_records = db.query(EvidenceHash).filter(EvidenceHash.evidence_id == ev.id).all()
            for h in hash_records:
                hash_event_id = f"EV_HASH_{h.id}"
                existing_hash = db.query(CustodyLog).filter(
                    CustodyLog.external_event_id == hash_event_id
                ).first()

                if not existing_hash:
                    verifier_name = "Hash Verification Engine"
                    verifier_id = str(h.verified_by) if h.verified_by else None
                    if h.verified_by:
                        v_user = db.query(User).filter(User.id == h.verified_by).first()
                        if v_user:
                            verifier_name = v_user.full_name or v_user.username

                    hash_time = h.verified_at or h.created_at or datetime.now(timezone.utc)
                    if hash_time.tzinfo is None:
                        hash_time = hash_time.replace(tzinfo=timezone.utc)

                    short_hash = f"{h.sha256_hash[:8]}...{h.sha256_hash[-8:]}" if h.sha256_hash else "None"
                    remarks = f"Cryptographic baseline SHA-256 registered ({short_hash}). Verification status: {h.integrity_status}."

                    CustodyService.create_log(
                        db=db,
                        evidence_id=ev_id_str,
                        case_id=str_case_id,
                        external_event_id=hash_event_id,
                        investigator_id=verifier_id,
                        investigator_name=verifier_name,
                        actor_role="System Automated" if not h.verified_by else "Cyber Expert",
                        action="HASH_GENERATED",
                        event_type="HASH_GENERATED",
                        title="Hash Generated",
                        result=h.integrity_status or "SUCCESS",
                        remarks=remarks,
                        source_reference="EVIDENCE_HASH_LEDGER",
                        is_system_action=h.verified_by is None,
                        actor_is_unverified=False,
                        timestamp=hash_time
                    )
