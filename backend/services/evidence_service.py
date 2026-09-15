from typing import List, Optional
import shutil
import mimetypes
from pathlib import Path
from uuid import uuid4
from fastapi import HTTPException, UploadFile, status
from sqlalchemy.orm import Session
from sqlalchemy import or_

from models.case import Case
from models.user import User
from models.evidence import Evidence
from models.evidence_hash import EvidenceHash
from services.hash_service import HashService
from services.hash_verification_service import HashVerificationService
from services.timeline_service import create_timeline_event
from services.notification_service import create_notification
from services.storage_service import StorageService, BASE_UPLOAD_DIR
from utils.zip_security import ZipSecurityValidator, SafeArchiveMember


def get_case_or_404(db: Session, case_identifier: str | int) -> Case:
    """
    Resolves a case seamlessly by either database integer PK (Case.id)
    or human-readable case string (Case.case_id).
    """
    ident_str = str(case_identifier).strip()

    if ident_str.isdigit():
        case = db.query(Case).filter(
            or_(
                Case.id == int(ident_str),
                Case.case_id == ident_str
            )
        ).first()
    else:
        case = db.query(Case).filter(
            Case.case_id.ilike(ident_str)
        ).first()

    if not case:
        raise HTTPException(
            status_code=404,
            detail=f"Case '{case_identifier}' not found"
        )

    return case


def authorize_case_access(
    db: Session,
    case_identifier: str | int,
    current_user: User
) -> Case:
    """
    Enforces strict role-based access for case-scoped evidence and hash verification:
    - Administrator (Role 1): Case creator must be in the same cyber_cell_id
    - Investigator (Role 2): Case.investigator_id == current_user.id
    - Cyber Expert (Role 3): Case.cyber_expert_id == current_user.id
    """
    case = get_case_or_404(db, case_identifier)

    # Administrator
    if current_user.role_id == 1:
        creator = db.query(User).filter(User.id == case.created_by).first()
        if not creator or creator.cyber_cell_id != current_user.cyber_cell_id:
            raise HTTPException(
                status_code=403,
                detail="Access denied: Case does not belong to your branch"
            )

    # Investigator
    elif current_user.role_id == 2:
        if case.investigator_id != current_user.id:
            raise HTTPException(
                status_code=403,
                detail="Access denied: You are not assigned to this case"
            )

    # Cyber Expert
    elif current_user.role_id == 3:
        if case.cyber_expert_id != current_user.id:
            raise HTTPException(
                status_code=403,
                detail="Access denied: You are not assigned as Cyber Expert to this case"
            )

    else:
        raise HTTPException(
            status_code=403,
            detail="Access denied: Unauthorized role"
        )

    return case


def generate_evidence_id(db: Session, case: Case, offset: int = 0) -> str:
    """
    Generates human-readable evidence ID (e.g., EV-1024-001).
    Supports offset for safe sequential batch generation without duplicate IDs.
    """
    case_code = (
        case.case_id
        .replace("CASE-", "")
        .replace("case-", "")
        .replace("C-", "")
        .strip()
    )
    if not case_code:
        case_code = str(case.id)

    existing_eids = [
        r[0] for r in db.query(Evidence.evidence_id)
        .filter(Evidence.case_id == case.id)
        .all()
    ]
    max_seq = 0
    prefix = f"EV-{case_code}-"
    for eid in existing_eids:
        if eid and eid.startswith(prefix):
            suffix = eid[len(prefix):]
            if suffix.isdigit():
                max_seq = max(max_seq, int(suffix))

    if max_seq == 0:
        max_seq = len(existing_eids)

    next_seq = max_seq + 1 + offset
    return f"EV-{case_code}-{next_seq:03d}"


def create_case_evidence(
    db: Session,
    case: Case,
    file_data: dict,
    current_user: User,
    original_hash: str | None = None
) -> tuple[Evidence, EvidenceHash]:
    """
    Creates evidence record, runs Member 5 HashService to generate real SHA-256,
    verifies integrity against trusted reference if provided, and records timeline.
    """
    # 1. Compute real current SHA-256 via Member 5 HashService
    current_sha256 = HashService.generate_sha256(file_data["file_path"])

    # 2. Evaluate integrity state (Verified, Tampered, or Unknown)
    verification = HashVerificationService.verify_evidence_integrity(
        original_hash=original_hash,
        current_hash=current_sha256,
        verified_by_user_id=current_user.id
    )

    # 3. Create Evidence DB record
    evidence_id = generate_evidence_id(db, case)
    new_evidence = Evidence(
        evidence_id=evidence_id,
        case_id=case.id,
        file_name=file_data["file_name"],
        file_type=file_data["file_type"],
        file_size=file_data["file_size"],
        file_path=file_data["file_path"],
        status="Active"
    )
    db.add(new_evidence)
    db.commit()
    db.refresh(new_evidence)

    # 4. Create EvidenceHash DB record
    new_hash = EvidenceHash(
        evidence_id=new_evidence.id,
        file_name=file_data["file_name"],
        sha256_hash=current_sha256,
        current_hash=current_sha256,
        original_hash=verification["original_hash"],
        hash_match=verification["hash_match"],
        tampered=verification["tampered"],
        integrity_status=verification["integrity_status"],
        verified_at=verification["verification_date"],
        verified_by=verification["verified_by"]
    )
    db.add(new_hash)
    db.flush()

    # 4b. Persist technical metadata record in MySQL
    try:
        from services.metadata_service import MetadataService
        MetadataService.persist_evidence_metadata(
            db=db,
            case=case,
            evidence=new_evidence,
            evidence_hash=new_hash,
            current_user=current_user
        )
    except Exception as e:
        print(f"Warning: Metadata persistence for {new_evidence.evidence_id} deferred: {e}")

    db.commit()
    db.refresh(new_hash)

    # 5. Timeline event
    role_name = "Cyber Expert" if current_user.role_id == 3 else (
        "Investigator" if current_user.role_id == 2 else "Administrator"
    )
    create_timeline_event(
        db=db,
        case_id=case.id,
        event=f"Evidence uploaded: {evidence_id} ({file_data['file_name']})",
        performed_by=current_user.id,
        performed_by_role=role_name
    )

    # 6. Event-Driven Notifications
    # Notify assigned Investigator (if not the uploader)
    if case.investigator_id and case.investigator_id != current_user.id:
        create_notification(
            db=db,
            title="Evidence Uploaded",
            message=f"New evidence '{file_data['file_name']}' added to case {case.case_id}.",
            notification_type="EVIDENCE_UPLOAD",
            user_id=case.investigator_id,
            cyber_cell_id=None
        )

    # Notify assigned Cyber Expert (if not the uploader)
    if case.cyber_expert_id and case.cyber_expert_id != current_user.id:
        create_notification(
            db=db,
            title="Evidence Uploaded",
            message=f"New evidence '{file_data['file_name']}' ready for technical analysis in case {case.case_id}.",
            notification_type="EVIDENCE_UPLOAD",
            user_id=case.cyber_expert_id,
            cyber_cell_id=None
        )

    # Critical Integrity Alert (only if tampering or mismatch detected)
    is_tampered = (
        verification.get("tampered") is True
        or verification.get("hash_match") is False
        or str(verification.get("integrity_status", "")).upper() in ["TAMPERED", "MISMATCH"]
    )
    if is_tampered:
        tamper_msg = f"CRITICAL: Evidence '{file_data['file_name']}' in case {case.case_id} failed integrity verification (Tampered/Mismatch)."
        if case.investigator_id:
            create_notification(
                db=db,
                title="Integrity Alert: Tampered Evidence",
                message=tamper_msg,
                notification_type="INTEGRITY_ALERT",
                user_id=case.investigator_id,
                cyber_cell_id=None
            )
        if case.cyber_expert_id:
            create_notification(
                db=db,
                title="Integrity Alert: Tampered Evidence",
                message=tamper_msg,
                notification_type="INTEGRITY_ALERT",
                user_id=case.cyber_expert_id,
                cyber_cell_id=None
            )
        # Notify Branch Admins responsible for this case
        branch_admins = (
            db.query(User)
            .filter(
                User.role_id == 1,
                User.cyber_cell_id == current_user.cyber_cell_id,
                User.is_active == True
            )
            .all()
        )
        for admin in branch_admins:
            create_notification(
                db=db,
                title="Integrity Alert: Tampered Evidence",
                message=tamper_msg,
                notification_type="INTEGRITY_ALERT",
                user_id=admin.id,
                cyber_cell_id=None
            )

    return new_evidence, new_hash


def get_case_evidence_list(db: Session, case: Case) -> list[dict]:
    """
    Returns evidence list belonging STRICTLY to the selected case.
    """
    records = (
        db.query(Evidence, EvidenceHash)
        .join(EvidenceHash, Evidence.id == EvidenceHash.evidence_id)
        .filter(Evidence.case_id == case.id)
        .order_by(Evidence.created_at.desc())
        .all()
    )

    results = []
    for ev, h in records:
        results.append({
            "evidence_id": ev.evidence_id,
            "file_name": ev.file_name,
            "file_type": ev.file_type,
            "file_size": ev.file_size,
            "uploaded_on": ev.created_at,
            "current_hash": h.current_hash,
            "integrity_status": h.integrity_status
        })

    return results


def get_evidence_details(
    db: Session,
    case: Case,
    evidence_identifier: str | int
) -> dict:
    """
    Returns single evidence hash verification details, verifying that
    the evidence belongs strictly to the authorized parent case.
    """
    ident_str = str(evidence_identifier).strip()

    if ident_str.isdigit():
        evidence = db.query(Evidence).filter(
            Evidence.case_id == case.id,
            or_(
                Evidence.id == int(ident_str),
                Evidence.evidence_id == ident_str
            )
        ).first()
    else:
        evidence = db.query(Evidence).filter(
            Evidence.case_id == case.id,
            Evidence.evidence_id.ilike(ident_str)
        ).first()

    if not evidence:
        raise HTTPException(
            status_code=404,
            detail=f"Evidence '{evidence_identifier}' not found for this case"
        )

    h = db.query(EvidenceHash).filter(
        EvidenceHash.evidence_id == evidence.id
    ).first()

    if not h:
        raise HTTPException(
            status_code=404,
            detail="Hash verification record not found for evidence"
        )

    verified_by_name = None
    if h.verified_by:
        verifier = db.query(User).filter(User.id == h.verified_by).first()
        if verifier:
            verified_by_name = verifier.full_name

    return {
        "evidence_id": evidence.evidence_id,
        "file_name": evidence.file_name,
        "file_type": evidence.file_type,
        "file_size": evidence.file_size,
        "uploaded_on": evidence.created_at,
        "file_path": evidence.file_path,
        "current_hash": h.current_hash,
        "original_hash": h.original_hash,
        "hash_match": h.hash_match,
        "tampered": h.tampered,
        "integrity_status": h.integrity_status,
        "verification_date": h.verified_at,
        "verified_by": verified_by_name
    }


async def ingest_zip_evidence_batch(
    db: Session,
    case: Case,
    archive: UploadFile,
    current_user: User
) -> dict:
    """
    Ingests a ZIP evidence archive for a case:
    1. Validates Admin role.
    2. Streams ZIP to staging and checks max archive size (100 MB).
    3. Calculates container package SHA-256 for audit provenance.
    4. Securely validates ZIP and extracts leaf files to sandbox via ZipSecurityValidator.
    5. In an atomic transaction:
       - Moves files to permanent case storage uploads/evidence/{case.id}/
       - Computes individual SHA-256 for each file
       - Creates Evidence and EvidenceHash records
       - Generates 1 batch timeline event
       - Dispatches 1 batch notification to assigned Investigator and Cyber Expert
    6. Commits transaction and cleans up staging sandbox.
    7. Rolls back DB and cleans up any permanent files copied on failure.
    """
    if current_user.role_id != 1:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Administrator access required for batch evidence ingestion"
        )

    orig_filename = Path(archive.filename or "archive.zip").name
    if not orig_filename.lower().endswith(".zip"):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Only .zip archive files are supported for batch evidence ingestion."
        )

    staging_root = Path("uploads/staging")
    staging_root.mkdir(parents=True, exist_ok=True)
    batch_uuid = uuid4().hex
    staging_zip = staging_root / f"upload_{batch_uuid}_{orig_filename}"

    # Stream upload archive to staging with size enforcement (100 MB)
    max_archive_bytes = 100 * 1024 * 1024
    total_uploaded = 0
    try:
        with open(staging_zip, "wb") as buffer:
            while chunk := await archive.read(1024 * 1024):
                total_uploaded += len(chunk)
                if total_uploaded > max_archive_bytes:
                    raise HTTPException(
                        status_code=status.HTTP_400_BAD_REQUEST,
                        detail="Archive size exceeds maximum permitted limit of 100 MB."
                    )
                buffer.write(chunk)
    except Exception as e:
        if staging_zip.exists():
            try:
                staging_zip.unlink()
            except Exception:
                pass
        if isinstance(e, HTTPException):
            raise e
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Failed to read uploaded archive: {str(e)}"
        )

    # Calculate Container Package SHA-256 on the uploaded archive
    archive_hash = HashService.generate_sha256(str(staging_zip))
    archive_size = staging_zip.stat().st_size

    # Validate and extract members safely into staging sandbox
    try:
        extracted_members, staging_dir = ZipSecurityValidator.validate_and_stage_zip(
            archive_path=staging_zip,
            staging_root=staging_root
        )
    finally:
        # We can safely delete the uploaded raw zip file once extracted/validated
        if staging_zip.exists():
            try:
                staging_zip.unlink()
            except Exception:
                pass

    case_dir = BASE_UPLOAD_DIR / str(case.id)
    case_dir.mkdir(parents=True, exist_ok=True)
    permanent_files_copied: List[Path] = []

    try:
        evidence_batch_items = []
        db_evidences = []

        for idx, member in enumerate(extracted_members):
            ext = Path(member.safe_name).suffix
            unique_name = f"{uuid4().hex}_{member.safe_name}"
            perm_dest = case_dir / unique_name

            # Copy from staging sandbox to permanent storage
            shutil.copy2(member.staged_path, perm_dest)
            permanent_files_copied.append(perm_dest)

            # Compute genuine individual SHA-256
            file_sha256 = HashService.generate_sha256(str(perm_dest))

            # Categorize file type
            mime_type, _ = mimetypes.guess_type(member.safe_name)
            file_category = StorageService._categorize_file_type(mime_type, ext)

            # Generate unique sequential evidence ID
            ev_id = generate_evidence_id(db, case, offset=idx)

            ev_model = Evidence(
                evidence_id=ev_id,
                case_id=case.id,
                file_name=member.relative_path,
                file_type=file_category,
                file_size=member.file_size,
                file_path=str(perm_dest).replace("\\", "/"),
                status="Active"
            )
            db.add(ev_model)
            db_evidences.append((ev_model, file_sha256, member))

        # Flush to populate primary keys for EvidenceHash
        db.flush()

        for ev_model, file_sha256, member in db_evidences:
            hash_model = EvidenceHash(
                evidence_id=ev_model.id,
                file_name=member.relative_path,
                sha256_hash=file_sha256,
                current_hash=file_sha256,
                original_hash=None,
                hash_match=None,
                tampered=False,
                integrity_status="Unknown",
                verified_at=None,
                verified_by=None
            )
            db.add(hash_model)

            # Persist technical metadata record in MySQL
            try:
                from services.metadata_service import MetadataService
                MetadataService.persist_evidence_metadata(
                    db=db,
                    case=case,
                    evidence=ev_model,
                    evidence_hash=hash_model,
                    current_user=current_user
                )
            except Exception as e:
                print(f"Warning: Metadata persistence for batch {ev_model.evidence_id} deferred: {e}")

            evidence_batch_items.append({
                "evidence_id": ev_model.evidence_id,
                "file_name": ev_model.file_name,
                "file_type": ev_model.file_type,
                "file_size": ev_model.file_size,
                "sha256_hash": file_sha256,
                "current_hash": file_sha256,
                "integrity_status": "Unknown",
                "uploaded_on": ev_model.created_at
            })

        # Single batch timeline event
        timeline_msg = (
            f"Batch evidence ingested from ZIP archive '{orig_filename}': "
            f"{len(extracted_members)} files added. "
            f"Container SHA-256: {archive_hash}"
        )
        create_timeline_event(
            db=db,
            case_id=case.id,
            event=timeline_msg,
            performed_by=current_user.id,
            performed_by_role="Administrator"
        )

        # Single batch notifications (strictly user-specific)
        if case.investigator_id and case.investigator_id != current_user.id:
            create_notification(
                db=db,
                title="Batch Evidence Uploaded",
                message=f"{len(extracted_members)} evidence files were added to case {case.case_id} from '{orig_filename}'.",
                notification_type="EVIDENCE_UPLOAD",
                user_id=case.investigator_id,
                cyber_cell_id=None
            )

        if case.cyber_expert_id and case.cyber_expert_id != current_user.id:
            create_notification(
                db=db,
                title="Batch Evidence Uploaded",
                message=f"{len(extracted_members)} evidence files in case {case.case_id} are ready for technical analysis.",
                notification_type="EVIDENCE_UPLOAD",
                user_id=case.cyber_expert_id,
                cyber_cell_id=None
            )

        # Commit entire batch transaction atomically
        db.commit()

        return {
            "success": True,
            "message": f"ZIP archive processed successfully: {len(extracted_members)} evidence files extracted and hashed.",
            "case_id": case.case_id,
            "archive_name": orig_filename,
            "archive_size": archive_size,
            "archive_hash": archive_hash,
            "total_files": len(extracted_members),
            "items": evidence_batch_items
        }

    except Exception as exc:
        db.rollback()
        for p_file in permanent_files_copied:
            try:
                if p_file.exists():
                    p_file.unlink()
            except Exception:
                pass

        if isinstance(exc, HTTPException):
            raise exc

        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Batch evidence ingestion failed: {str(exc)}"
        )
    finally:
        ZipSecurityValidator.cleanup_staging(staging_dir)

