from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from database.database import get_db
from schemas.change_password import ChangePasswordRequest
from services.change_password_service import change_password

router = APIRouter(
    prefix="/change-password",
    tags=["Change Password"]
)


@router.put("/")
def change_user_password(
    password_data: ChangePasswordRequest,
    db: Session = Depends(get_db)
):
    return change_password(
        db,
        password_data
    )