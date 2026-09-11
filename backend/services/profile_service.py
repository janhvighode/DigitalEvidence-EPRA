from sqlalchemy.orm import Session

from models.user import User
from models.role import Role
from models.cyber_cell import CyberCell


def get_profile(db: Session, user_id: int):

    result = (
        db.query(
            User,
            Role.role_name,
            CyberCell.cyber_cell_name
        )
        .join(Role, User.role_id == Role.id)
        .join(CyberCell, User.cyber_cell_id == CyberCell.id)
        .filter(User.id == user_id)
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
        "cyber_cell_id": user.cyber_cell_id,
        "cyber_cell": cyber_cell_name
    }


def update_profile(
    db: Session,
    user_id: int,
    data
):

    user = (
        db.query(User)
        .filter(User.id == user_id)
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

    return get_profile(db, user_id)