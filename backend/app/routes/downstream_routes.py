from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.database import get_db
from app.services.downstream_service import DownstreamService
from app.services.hash_manifest_service import validate_safe_id

router = APIRouter(
    prefix="/downstream",
    tags=["Downstream EPRA Data Contract"]
)


@router.get("/epra/{case_id}")
def get_downstream_epra_contract(
    case_id: str,
    db: Session = Depends(get_db)
):
    """
    Expose Member 5's proposed structured data contract for the downstream EPRA module.
    Contains case reference, technical metadata, baseline hashes, latest current hashes,
    integrity statuses, verification timestamps, and complete chain of custody trails.

    Notice: This represents Member 5's proposed structured export. End-to-end EPRA integration
    and suspect scoring algorithms reside in the downstream EPRA prioritization module.
    """
    try:
        clean_case_id = validate_safe_id(case_id, "case_id")
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

    try:
        payload = DownstreamService.get_epra_payload(db=db, case_id=clean_case_id)
        return payload
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
