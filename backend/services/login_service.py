from sqlalchemy.orm import Session
from passlib.context import CryptContext

from models.user import User
from schemas.login import LoginRequest
from utils.jwt_handler import create_access_token


pwd_context = CryptContext(
    schemes=["bcrypt"],
    deprecated="auto"
)


def login_user(
    db: Session,
    login_data: LoginRequest
):

    user = db.query(User).filter(
        User.username == login_data.username
    ).first()

    if not user:
        return {
            "success": False,
            "message": "Invalid username or password."
        }

    if not pwd_context.verify(
        login_data.password,
        user.password
    ):
        return {
            "success": False,
            "message": "Invalid username or password."
        }

    if not user.is_active:
        return {
            "success": False,
            "message": "Your account is inactive."
        }

    access_token = create_access_token(
        {
            "user_id": user.id,
            "username": user.username,
            "role_id": user.role_id
        }
    )

    return {
        "success": True,
        "message": "Login successful.",
        "access_token": access_token,
        "token_type": "bearer",
        "is_first_login": user.is_first_login
    }