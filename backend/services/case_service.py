from sqlalchemy.orm import Session

from models.case import Case
from models.user import User
from schemas.case import CaseCreate

import random


def generate_case_id():
    number = random.randint(1000, 9999)
    return f"CASE-{number}"


def create_case(
    db: Session,
    case: CaseCreate,
    current_user: User
):

    # ==========================================
    # VALIDATE INVESTIGATOR
    # ==========================================

    if case.investigator_id is not None:

        investigator = db.query(User).filter(
            User.id == case.investigator_id,
            User.role_id == 2,
            User.cyber_cell_id ==
            current_user.cyber_cell_id,
            User.is_active == True
        ).first()

        if not investigator:
            return {
                "success": False,
                "message": "Invalid Investigator for your branch."
            }


    # ==========================================
    # VALIDATE CYBER EXPERT
    # ==========================================

    if case.cyber_expert_id is not None:

        cyber_expert = db.query(User).filter(
            User.id == case.cyber_expert_id,
            User.role_id == 3,
            User.cyber_cell_id ==
            current_user.cyber_cell_id,
            User.is_active == True
        ).first()

        if not cyber_expert:
            return {
                "success": False,
                "message": "Invalid Cyber Expert for your branch."
            }


    # ==========================================
    # CREATE CASE
    # ==========================================

    new_case = Case(
        case_id=generate_case_id(),
        title=case.title,
        description=case.description,
        investigator_id=case.investigator_id,
        cyber_expert_id=case.cyber_expert_id,
        priority=case.priority,
        status="Open",
        created_by=current_user.id
    )

    db.add(new_case)
    db.commit()
    db.refresh(new_case)

    return new_case