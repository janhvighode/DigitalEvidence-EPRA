from sqlalchemy.orm import Session
from models.role import Role


def get_all_roles(db: Session):
    roles = db.query(Role).all()
    return roles