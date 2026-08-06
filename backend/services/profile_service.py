from sqlalchemy.orm import Session

from models.user import User
from models.role import Role
from models.cyber_cell import CyberCell


# Temporary Administrator ID
ADMIN_ID = 1


def get_profile(db: Session):

    result = (
        db.query(
            User,
            Role.role_name,
            CyberCell.cyber_cell_name
        )
        .join(Role, User.role_id == Role.id)
        .join(CyberCell, User.cyber_cell_id == CyberCell.id)
        .filter(User.id == ADMIN_ID)
        .first()
    )

    if result is None:
        return None

    user, role_name, cyber_cell_name = result

    return {
        "id": user.id,
        "full_name": user.full_name,
        "username": user.username,
        "email": user.email,
        "phone_number": user.phone_number,
        "role": role_name,
        "cyber_cell": cyber_cell_name
    }


def update_profile(db: Session, data):

    user = (
        db.query(User)
        .filter(User.id == ADMIN_ID)
        .first()
    )

    if user is None:
        return None

    if data.full_name is not None:
        user.full_name = data.full_name

    if data.phone_number is not None:
        user.phone_number = data.phone_number

    db.commit()
    db.refresh(user)

    return get_profile(db)