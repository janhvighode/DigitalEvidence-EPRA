from pathlib import Path

from fastapi import APIRouter, UploadFile, File, HTTPException

from app.services.file_hash_service import FileHashService


router = APIRouter(
    prefix="/hash",
    tags=["Hash Generation"]
)


UPLOAD_DIR = Path("app/uploads/hash_input")
UPLOAD_DIR.mkdir(parents=True, exist_ok=True)


@router.post("/upload")
async def upload_and_generate_hash(
    file: UploadFile = File(...)
):
    """
    Upload any file and generate its SHA-256 hash.
    """

    try:

        file_path = UPLOAD_DIR / file.filename

        with open(file_path, "wb") as output_file:

            while chunk := await file.read(1024 * 1024):
                output_file.write(chunk)

        sha256 = FileHashService.generate_sha256(
            str(file_path)
        )

        return {
            "status": "success",
            "file_name": file.filename,
            "sha256": sha256
        }

    except Exception as e:

        raise HTTPException(
            status_code=500,
            detail=str(e)
        )