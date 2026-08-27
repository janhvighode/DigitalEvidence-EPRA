from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from database.database import get_db

from schemas.forgot_password import ForgotPasswordRequest
from schemas.reset_password import ResetPasswordRequest

from services.forgot_password_service import (
    forgot_password,
    reset_password
)

router = APIRouter(
    prefix="",
    tags=["Forgot Password"]
)


@router.post("/forgot-password")
def forgot_password_route(
    request: ForgotPasswordRequest,
    db: Session = Depends(get_db)
):
    return forgot_password(
        db,
        request
    )


@router.post("/reset-password")
def reset_password_route(
    request: ResetPasswordRequest,
    db: Session = Depends(get_db)
):
    return reset_password(
        db,
        request
    )