from pathlib import Path
from uuid import uuid4
from typing import Annotated

from fastapi import APIRouter, UploadFile, File, HTTPException

from app.services.file_hash_service import FileHashService


router = APIRouter(
    prefix="/hash",
    tags=["Hash Generation"]
)


# ============================================================
# SINGLE FILE UPLOAD
# ============================================================

UPLOAD_DIR = Path("app/uploads/hash_input")
UPLOAD_DIR.mkdir(parents=True, exist_ok=True)


@router.post("/upload")
async def upload_and_generate_hash(
    file: Annotated[
        UploadFile,
        File(description="Upload a single evidence file")
    ]
):
    """
    Upload one evidence file and generate its SHA-256 hash.
    """

    try:

        original_filename = Path(
            file.filename or "unknown"
        ).name

        if not original_filename:
            raise HTTPException(
                status_code=400,
                detail="Invalid file name."
            )

        stored_filename = (
            f"{uuid4()}_{original_filename}"
        )

        file_path = UPLOAD_DIR / stored_filename

        total_size = 0

        with open(file_path, "wb") as output_file:

            while chunk := await file.read(1024 * 1024):

                output_file.write(chunk)
                total_size += len(chunk)

        sha256 = FileHashService.generate_sha256(
            str(file_path)
        )

        return {
            "status": "success",
            "file_name": original_filename,
            "file_size_bytes": total_size,
            "sha256": sha256
        }

    except HTTPException:
        raise

    except Exception as e:

        raise HTTPException(
            status_code=500,
            detail=str(e)
        )


# ============================================================
# MULTIPLE FILE UPLOAD
# ============================================================

MULTI_UPLOAD_DIR = Path("app/uploads/hash_batch")
MULTI_UPLOAD_DIR.mkdir(parents=True, exist_ok=True)


@router.post("/upload-multiple")
async def upload_multiple_and_generate_hash(
    files: Annotated[
        list[UploadFile],
        File(description="Upload multiple evidence files")
    ]
):
    """
    Upload multiple evidence files and generate
    an individual SHA-256 hash for every file.
    """

    if not files:

        raise HTTPException(
            status_code=400,
            detail="No files uploaded."
        )

    results = []

    for file in files:

        original_filename = Path(
            file.filename or "unknown"
        ).name

        if not original_filename:
            continue

        stored_filename = (
            f"{uuid4()}_{original_filename}"
        )

        file_path = MULTI_UPLOAD_DIR / stored_filename

        try:

            total_size = 0

            with open(file_path, "wb") as output_file:

                while chunk := await file.read(1024 * 1024):

                    output_file.write(chunk)
                    total_size += len(chunk)

            sha256 = FileHashService.generate_sha256(
                str(file_path)
            )

            results.append({
                "file_name": original_filename,
                "file_size_bytes": total_size,
                "sha256": sha256,
                "status": "Hash Generated"
            })

        except Exception as e:

            results.append({
                "file_name": original_filename,
                "status": "Failed",
                "error": str(e)
            })

    return {
        "status": "success",
        "total_files": len(results),
        "files": results
    }


# ============================================================
# HASH MANIFEST GENERATION
# ============================================================

from app.services.hash_manifest_service import HashManifestService


@router.post("/generate-manifest")
async def generate_hash_manifest(
    case_id: str,
    files: list[UploadFile] = File(...)
):
    """
    Upload evidence files, generate SHA-256 hashes,
    and create a JSON hash manifest for the case.
    """

    if not case_id.strip():
        raise HTTPException(
            status_code=400,
            detail="Case ID is required."
        )

    if not files:
        raise HTTPException(
            status_code=400,
            detail="No evidence files uploaded."
        )

    evidence_records = []

    for file in files:

        original_filename = Path(
            file.filename or "unknown"
        ).name

        if not original_filename:
            continue

        stored_filename = (
            f"{uuid4()}_{original_filename}"
        )

        file_path = MULTI_UPLOAD_DIR / stored_filename

        try:

            total_size = 0

            with open(file_path, "wb") as output_file:

                while chunk := await file.read(1024 * 1024):

                    output_file.write(chunk)
                    total_size += len(chunk)

            sha256 = FileHashService.generate_sha256(
                str(file_path)
            )

            evidence_records.append({
                "file_name": original_filename,
                "file_size_bytes": total_size,
                "sha256": sha256,
                "hash_algorithm": "SHA-256",
                "status": "Hash Generated"
            })

        except Exception as e:

            evidence_records.append({
                "file_name": original_filename,
                "status": "Failed",
                "error": str(e)
            })

    if not evidence_records:

        raise HTTPException(
            status_code=400,
            detail="No valid evidence files processed."
        )

    manifest = HashManifestService.create_manifest(
        case_id=case_id,
        evidence_records=evidence_records
    )

    manifest_path = HashManifestService.save_manifest(
        manifest
    )

    return {
        "status": "success",
        "case_id": case_id,
        "hash_algorithm": "SHA-256",
        "total_evidence_files": len(evidence_records),
        "manifest_file": manifest_path,
        "evidence": evidence_records
    }
# ============================================================
# HASH MANIFEST DOWNLOAD
# ============================================================

from fastapi.responses import FileResponse


MANIFEST_DIR = Path("app/uploads/hash_manifests")


@router.get("/download-manifest/{case_id}")
async def download_hash_manifest(case_id: str):
    """
    Download the latest SHA-256 hash manifest
    generated for a specific case.
    """

    if not case_id.strip():
        raise HTTPException(
            status_code=400,
            detail="Case ID is required."
        )

    if not MANIFEST_DIR.exists():
        raise HTTPException(
            status_code=404,
            detail="No hash manifests found."
        )

    # Find all manifests belonging to the case
    manifest_files = list(
        MANIFEST_DIR.glob(
            f"{case_id}_hash_manifest_*.json"
        )
    )

    if not manifest_files:
        raise HTTPException(
            status_code=404,
            detail=f"No hash manifest found for case: {case_id}"
        )

    # Select latest generated manifest
    latest_manifest = max(
        manifest_files,
        key=lambda file: file.stat().st_mtime
    )

    return FileResponse(
        path=str(latest_manifest),
        media_type="application/json",
        filename=latest_manifest.name
    )