from pydantic import BaseModel


class ChangePasswordRequest(BaseModel):
    username: str
    old_password: str
    new_password: str
    confirm_password: str