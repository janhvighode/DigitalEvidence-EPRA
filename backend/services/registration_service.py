from sqlalchemy.orm import Session

from models.user import User
from models.cyber_cell import CyberCell
from services.notification_service import create_notification
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

    admins = (
    db.query(User)
    .join(
        CyberCell,
        User.cyber_cell_id == CyberCell.id
    )
    .filter(
        User.role_id == 1,
        User.is_active == True,
        CyberCell.city_id == registration.city_id
    )
    .all()
)

    for admin in admins:
        create_notification(
        db=db,
        title="New Registration Request",
        message=(
            f"New registration request received "
            f"from {registration.full_name}."
        ),
        notification_type="registration",
        user_id=admin.id
    )

    return {
        "success": True,
        "message": "Registration request submitted successfully."
    }