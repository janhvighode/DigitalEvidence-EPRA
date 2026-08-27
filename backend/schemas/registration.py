from pydantic import BaseModel, EmailStr


class RegistrationRequestCreate(BaseModel):
    full_name: str
    email: EmailStr
    phone_number: str
    requested_role_id: int
    city_id: int
    cyber_cell_id: int