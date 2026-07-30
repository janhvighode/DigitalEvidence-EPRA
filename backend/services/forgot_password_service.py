from datetime import datetime, timedelta

from sqlalchemy.orm import Session
from passlib.context import CryptContext

from models.user import User
from models.password_reset_otp import PasswordResetOTP

from schemas.forgot_password import ForgotPasswordRequest
from schemas.reset_password import ResetPasswordRequest

from utils.otp_generator import generate_otp
from utils.password_validator import validate_password

from services.email_service import send_email


pwd_context = CryptContext(
    schemes=["bcrypt"],
    deprecated="auto"
)


def forgot_password(
    db: Session,
    request: ForgotPasswordRequest
):

    user = db.query(User).filter(
        User.email == request.email
    ).first()

    if not user:
        return {
            "success": False,
            "message": "No account found with this email."
        }

    db.query(
        PasswordResetOTP
    ).filter(
        PasswordResetOTP.email == request.email
    ).delete()

    otp = generate_otp()

    otp_record = PasswordResetOTP(
        email=request.email,
        otp=otp,
        expires_at=datetime.utcnow() + timedelta(minutes=5)
    )

    db.add(otp_record)

    db.commit()

    email_body = f"""
Hello {user.full_name},

Your OTP for password reset is:

{otp}

This OTP is valid for 5 minutes.

If you did not request this request, please ignore this email.

Regards,
Smart Digital Evidence Prioritization System
"""

    email_sent = send_email(
        request.email,
        "Password Reset OTP",
        email_body
    )

    if not email_sent:
        return {
            "success": False,
            "message": "OTP generated but email could not be sent."
        }

    return {
        "success": True,
        "message": "OTP sent successfully."
    }


def reset_password(
    db: Session,
    request: ResetPasswordRequest
):

    user = db.query(User).filter(
        User.email == request.email
    ).first()

    if not user:
        return {
            "success": False,
            "message": "User not found."
        }

    otp_record = db.query(
        PasswordResetOTP
    ).filter(
        PasswordResetOTP.email == request.email
    ).first()

    if not otp_record:
        return {
            "success": False,
            "message": "OTP not found."
        }

    if otp_record.otp != request.otp:
        return {
            "success": False,
            "message": "Invalid OTP."
        }

    if datetime.utcnow() > otp_record.expires_at:

        db.delete(otp_record)
        db.commit()

        return {
            "success": False,
            "message": "OTP has expired."
        }

    if request.new_password != request.confirm_password:
        return {
            "success": False,
            "message": "New password and Confirm password do not match."
        }

    validation = validate_password(
        request.new_password
    )

    if validation:
        return {
            "success": False,
            "message": validation
        }

    new_hash = pwd_context.hash(
        request.new_password
    )

    print("========== DEBUG ==========")
    print("Old Hash :", user.password)
    print("New Hash :", new_hash)

    user.password = new_hash
    user.is_first_login = False

    print("After Assignment :", user.password)

    db.add(user)

    db.delete(otp_record)

    db.commit()

    db.refresh(user)

    print("After Commit :", user.password)
    print("===========================")

    return {
        "success": True,
        "message": "Password reset successfully."
    }