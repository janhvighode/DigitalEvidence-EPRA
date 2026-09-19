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
        crime_type=case.crime_type,
        investigator_id=case.investigator_id,
        cyber_expert_id=case.cyber_expert_id,
        priority=case.priority,
        status="Open",
        created_by=current_user.id
    )

    db.add(new_case)
    db.commit()
    db.refresh(new_case)

    # Notifications for case assignment
    from services.notification_service import create_notification

    if new_case.investigator_id:
        create_notification(
            db=db,
            title="New Case Assigned",
            message=f"{new_case.case_id} has been assigned to you.",
            notification_type="CASE_ASSIGNMENT",
            user_id=new_case.investigator_id,
            cyber_cell_id=None
        )

    if new_case.cyber_expert_id:
        create_notification(
            db=db,
            title="New Case Assigned",
            message=f"{new_case.case_id} has been assigned to you.",
            notification_type="CASE_ASSIGNMENT",
            user_id=new_case.cyber_expert_id,
            cyber_cell_id=None
        )

    # Admin: Case Assignment Required if any role is unassigned
    if new_case.investigator_id is None or new_case.cyber_expert_id is None:
        missing_roles = []
        if new_case.investigator_id is None:
            missing_roles.append("Investigator")
        if new_case.cyber_expert_id is None:
            missing_roles.append("Cyber Expert")
        create_notification(
            db=db,
            title="Case Assignment Required",
            message=f"Case {new_case.case_id} was created and requires {' and '.join(missing_roles)} assignment.",
            notification_type="CASE_ASSIGNMENT_REQUIRED",
            user_id=current_user.id,
            cyber_cell_id=None
        )

    return new_case