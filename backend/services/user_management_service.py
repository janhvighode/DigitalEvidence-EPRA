from sqlalchemy.orm import Session
from models.user import User


def get_all_users(db: Session):
    return db.query(User).all()


def get_user_by_id(db: Session, user_id: int):
    return db.query(User).filter(User.id == user_id).first()


def search_users(db: Session, keyword: str):
    return db.query(User).filter(
        User.full_name.ilike(f"%{keyword}%") |
        User.email.ilike(f"%{keyword}%")
    ).all()


def update_user(db: Session, user_id: int, user_data):
    user = db.query(User).filter(User.id == user_id).first()

    if not user:
        return None

    if user_data.full_name is not None:
        user.full_name = user_data.full_name

    if user_data.phone_number is not None:
        user.phone_number = user_data.phone_number

    if user_data.cyber_cell_id is not None:
        user.cyber_cell_id = user_data.cyber_cell_id

    db.commit()
    db.refresh(user)

    return user


def change_user_status(db: Session, user_id: int, is_active: bool):
    user = db.query(User).filter(User.id == user_id).first()

    if not user:
        return None

    user.is_active = is_active

    db.commit()
    db.refresh(user)

    return {
    "message": "User status updated successfully",
    "user_id": user.id,
    "is_active": user.is_active
}

def get_investigators_by_cyber_cell(
    db: Session,
    cyber_cell_id: int
):
    investigators = db.query(User).filter(
        User.role_id == 2,
        User.cyber_cell_id == cyber_cell_id,
        User.is_active == True
    ).all()

    return investigators