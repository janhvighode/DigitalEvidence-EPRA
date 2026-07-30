from pydantic import BaseModel, EmailStr


class ResetPasswordRequest(BaseModel):

    email: EmailStr

    otp: str

    new_password: str

    confirm_password: str