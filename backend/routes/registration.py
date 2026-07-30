from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from database.database import get_db
from schemas.registration import RegistrationRequestCreate
from services.registration_service import create_registration_request

router = APIRouter(
    prefix="/register",
    tags=["Registration"]
)


@router.post("/")
def register(
    registration: RegistrationRequestCreate,
    db: Session = Depends(get_db)
):
    return create_registration_request(
        db,
        registration
    )