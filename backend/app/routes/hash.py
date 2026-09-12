from pathlib import Path
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, Query, Form
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session

from app.database import get_db, MANIFEST_DIR
from app.services.hash_manifest_service import HashManifestService, validate_safe_id
from app.services.metadata_service import MetadataService
from app.models.evidence_record import EvidenceRecord
from app.models.report_record import ReportRecord

router = APIRouter(
    prefix="/hash",
    tags=["Hash Manifest & Verification Display"]
)


# ============================================================
# HASH MANIFEST GENERATION (WITHOUT RE-UPLOADING OR HASHING)
# ============================================================

@router.post("/generate-manifest")
def generate_hash_manifest(
    case_id: str = Form(..., description="Case identifier to export existing hashes for"),
    investigator_name: Optional[str] = Form("Investigator"),
    investigator_id: Optional[str] = Form(None),
    db: Session = Depends(get_db)
):
    """
    Generate a JSON hash manifest for a case from existing recorded evidence and hashes.
    In accordance with confirmed module ownership, Member 5 does NOT recalculate SHA-256 hashes.
    Existing supplied hashes are serialized; any missing hashes are clearly flagged.
    """
    try:
        clean_case_id = validate_safe_id(case_id, "case_id")
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

    # Sync from adapter
    MetadataService.sync_case_from_adapter(db, clean_case_id)

    records = db.query(EvidenceRecord).filter(
        EvidenceRecord.case_id == clean_case_id
    ).order_by(EvidenceRecord.id.asc()).all()

    if not records:
        raise HTTPException(
            status_code=404,
            detail=f"No evidence records found for case: {clean_case_id}"
        )

    evidence_items = []
    missing_hash_count = 0

    for r in records:
        ev_id = r.external_evidence_id or str(r.id)
        has_hash = bool(r.original_sha256)
        if not has_hash:
            missing_hash_count += 1

        evidence_items.append({
            "evidence_id": ev_id,
            "file_name": r.original_filename,
            "file_size_bytes": r.file_size_bytes or 0,
            "sha256": r.original_sha256,
            "current_sha256": r.current_sha256,
            "hash_algorithm": "SHA-256",
            "hash_status": "AVAILABLE" if has_hash else "MISSING_HASH",
            "verification_status": r.verification_status or "Unknown"
        })

    manifest = HashManifestService.create_manifest(
        case_id=clean_case_id,
        evidence_records=evidence_items
    )
    manifest["investigator_name"] = investigator_name
    manifest["investigator_id"] = investigator_id
    manifest["missing_hashes_count"] = missing_hash_count

    manifest_path = HashManifestService.save_manifest(manifest)

    return {
        "status": "success",
        "case_id": clean_case_id,
        "hash_algorithm": "SHA-256",
        "total_evidence_files": len(evidence_items),
        "missing_hashes_count": missing_hash_count,
        "manifest_file": manifest_path,
        "evidence": evidence_items
    }


# ============================================================
# HASH MANIFEST DOWNLOAD
# ============================================================

@router.get("/download-manifest/{case_id}")
def download_hash_manifest(case_id: str):
    """
    Download the latest SHA-256 hash manifest generated for a specific case.
    Validates case_id strictly and prevents path traversal.
    """
    try:
        clean_case_id = validate_safe_id(case_id, "case_id")
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

    try:
        latest_manifest = HashManifestService.get_latest_manifest(clean_case_id)
        return FileResponse(
            path=str(latest_manifest),
            media_type="application/json",
            filename=latest_manifest.name
        )
    except FileNotFoundError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except PermissionError as e:
        raise HTTPException(status_code=403, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))