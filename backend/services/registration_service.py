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

    # ==========================================
    # CHECK DUPLICATE EMAIL
    # ==========================================

    existing_request = (
        db.query(RegistrationRequest)
        .filter(
            RegistrationRequest.email == registration.email
        )
        .first()
    )

    if existing_request:
        return {
            "success": False,
            "message": "Email already exists."
        }


    # ==========================================
    # CREATE REGISTRATION REQUEST
    # ==========================================

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


    # ==========================================
    # FIND ADMINISTRATORS FOR NOTIFICATION
    # ==========================================

    if registration.requested_role_id == 1:

        # --------------------------------------
        # NEW ADMINISTRATOR
        # --------------------------------------
        # Notify ALL existing active Administrators

        admins = (
            db.query(User)
            .filter(
                User.role_id == 1,
                User.is_active == True
            )
            .all()
        )

    elif registration.requested_role_id in [2, 3]:

        # --------------------------------------
        # INVESTIGATOR / CYBER EXPERT
        # --------------------------------------
        # Notify ONLY same Cyber Cell Admin(s)

        admins = (
            db.query(User)
            .filter(
                User.role_id == 1,
                User.is_active == True,
                User.cyber_cell_id == registration.cyber_cell_id
            )
            .all()
        )

    else:

        admins = []


    # ==========================================
    # DEBUG
    # ==========================================

    print(
        "REGISTRATION ROLE:",
        registration.requested_role_id
    )

    print(
        "REGISTRATION CYBER CELL:",
        registration.cyber_cell_id
    )

    print(
        "ADMINS FOUND:",
        len(admins)
    )


    # ==========================================
    # CREATE PERSONAL NOTIFICATION
    # ==========================================

    for admin in admins:

        print(
            "NOTIFICATION FOR ADMIN:",
            admin.id,
            admin.full_name
        )

        create_notification(
            db=db,
            title="New Registration Request",
            message=(
                f"New registration request received "
                f"from {registration.full_name}."
            ),
            notification_type="registration",

            # Personal notification
            user_id=admin.id,

            # Don't use branch scope for registration notification
            cyber_cell_id=None
        )


    # ==========================================
    # SUCCESS
    # ==========================================

    return {
        "success": True,
        "message": "Registration request submitted successfully."
    }