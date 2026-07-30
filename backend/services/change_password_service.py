from utils.password_validator import validate_password
from sqlalchemy.orm import Session
from passlib.context import CryptContext

from models.user import User
from schemas.change_password import ChangePasswordRequest

pwd_context = CryptContext(
    schemes=["bcrypt"],
    deprecated="auto"
)

def change_password(
    db: Session,
    password_data: ChangePasswordRequest
):

    user = db.query(User).filter(
        User.username == password_data.username
    ).first()

    if not user:
        return {
            "success": False,
            "message": "User not found."
        }

    if not pwd_context.verify(
        password_data.old_password,
        user.password
    ):
        return {
            "success": False,
            "message": "Old password is incorrect."
        }

    if password_data.new_password != password_data.confirm_password:
        return {
            "success": False,
            "message": "New password and Confirm password do not match."
        }

    if password_data.old_password == password_data.new_password:
        return {
            "success": False,
            "message": "New password cannot be the same as the old password."
        }

    validation = validate_password(
        password_data.new_password
    )

    if validation:
        return {
            "success": False,
            "message": validation
        }

    user.password = pwd_context.hash(
        password_data.new_password
    )

    user.is_first_login = False

    db.commit()

    db.refresh(user)

    return {
        "success": True,
        "message": "Password changed successfully."
    }