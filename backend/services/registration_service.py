from sqlalchemy.orm import Session

from models.registration_request import RegistrationRequest
from schemas.registration import RegistrationRequestCreate


def create_registration_request(
    db: Session,
    registration: RegistrationRequestCreate
):

    existing_request = db.query(RegistrationRequest).filter(
        RegistrationRequest.email == registration.email
    ).first()

    if existing_request:
        return {
            "success": False,
            "message": "Email already exists."
        }

    new_request = RegistrationRequest(
        full_name=registration.full_name,
        email=registration.email,
        phone_number=registration.phone_number,
        requested_role_id=registration.requested_role_id,
        city_id=registration.city_id,
        cyber_cell_id=registration.cyber_cell_id,
        status="Pending"
    )

    db.add(new_request)

    db.commit()

    db.refresh(new_request)

    return {
        "success": True,
        "message": "Registration request submitted successfully."
    }