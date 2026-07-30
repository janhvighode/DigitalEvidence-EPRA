from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from database.database import get_db
from schemas.login import LoginRequest
from services.login_service import login_user

router = APIRouter(
    prefix="/login",
    tags=["Login"]
)


@router.post("/")
def login(
    login_data: LoginRequest,
    db: Session = Depends(get_db)
):
    return login_user(
        db,
        login_data
    )