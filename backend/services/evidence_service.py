from typing import List
from fastapi import HTTPException
from sqlalchemy.orm import Session
from sqlalchemy import or_

from models.case import Case
from models.user import User
from models.evidence import Evidence
from models.evidence_hash import EvidenceHash
from services.hash_service import HashService
from services.hash_verification_service import HashVerificationService
from services.timeline_service import create_timeline_event


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


def generate_evidence_id(db: Session, case: Case) -> str:
    """
    Generates human-readable evidence ID (e.g., EV-1024-001).
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

    count = db.query(Evidence).filter(
        Evidence.case_id == case.id
    ).count() + 1

    return f"EV-{case_code}-{count:03d}"


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
