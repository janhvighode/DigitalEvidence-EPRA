from passlib.context import CryptContext

from models.user import User
from models.cyber_cell import CyberCell

from utils.username_generator import generate_unique_username
from utils.password_generator import generate_temporary_password
from utils.email_templates import registration_approved_template
from services.email_service import send_email
from sqlalchemy.orm import Session

from models.registration_request import RegistrationRequest

pwd_context = CryptContext(
    schemes=["bcrypt"],
    deprecated="auto"
)


def get_pending_registrations(db: Session):

    pending_requests = db.query(
        RegistrationRequest
    ).filter(
        RegistrationRequest.status == "Pending"
    ).all()

    result = []

    for request in pending_requests:

        result.append(
            {
                "id": request.id,
                "full_name": request.full_name,
                "email": request.email,
                "phone_number": request.phone_number,
                "requested_role_id": request.requested_role_id,
                "city_id": request.city_id,
                "cyber_cell_id": request.cyber_cell_id,
                "status": request.status,
                "created_at": request.created_at
            }
        )

    return result

def reject_registration(
    db: Session,
    registration_id: int
):

    registration = db.query(
        RegistrationRequest
    ).filter(
        RegistrationRequest.id == registration_id
    ).first()

    if not registration:
        return {
            "success": False,
            "message": "Registration request not found."
        }

    if registration.status == "Rejected":
        return {
            "success": False,
            "message": "Registration request is already rejected."
        }

    if registration.status == "Approved":
        return {
            "success": False,
            "message": "Approved registration cannot be rejected."
        }

    registration.status = "Rejected"

    db.commit()
    db.refresh(registration)

    return {
        "success": True,
        "message": "Registration request rejected successfully."
    }
def approve_registration(
    db: Session,
    registration_id: int
):

    registration = db.query(
        RegistrationRequest
    ).filter(
        RegistrationRequest.id == registration_id
    ).first()

    if not registration:
        return {
            "success": False,
            "message": "Registration request not found."
        }

    if registration.status == "Approved":
        return {
            "success": False,
            "message": "Registration already approved."
        }

    if registration.status == "Rejected":
        return {
            "success": False,
            "message": "Rejected registration cannot be approved."
        }

    cyber_cell = db.query(
        CyberCell
    ).filter(
        CyberCell.id == registration.cyber_cell_id
    ).first()

    if not cyber_cell:
        return {
            "success": False,
            "message": "Cyber Cell not found."
        }

    existing_user = db.query(User).filter(
        User.email == registration.email
    ).first()

    if existing_user:
        return {
            "success": False,
            "message": "User already exists."
        }

    username = generate_unique_username(
        db,
        registration.full_name,
        cyber_cell.cyber_cell_name
    )

    temporary_password = generate_temporary_password()

    print("Temporary Password:", temporary_password)
    print("Type:", type(temporary_password))
    print("Length:", len(temporary_password))

    hashed_password = pwd_context.hash(
        temporary_password
    )
    
    new_user = User(
        full_name=registration.full_name,
        username=username,
        email=registration.email,
        phone_number=registration.phone_number,
        password=hashed_password,
        role_id=registration.requested_role_id,
        cyber_cell_id=registration.cyber_cell_id,
        is_first_login=True,
        is_active=True
    )

    db.add(new_user)

    registration.status = "Approved"

    db.commit()

    db.refresh(new_user)

    email_body = registration_approved_template(
        registration.full_name,
        username,
        temporary_password
    )

    email_sent = send_email(
        registration.email,
        "Registration Approved",
        email_body
    )

    if not email_sent:
        return {
            "success": False,
            "message": "User created successfully, but email could not be sent."
        }

    return {
        "success": True,
        "message": "Registration approved successfully.",
        "username": username
    }