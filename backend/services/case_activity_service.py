from sqlalchemy.orm import Session

from models.case import Case
from models.user import User
from services.timeline_service import create_timeline_event
from services.notification_service import create_notification



def get_case_board(db: Session):

    cases = (
    db.query(Case)
    .outerjoin(User, Case.investigator_id == User.id)
    .add_columns(User.full_name)
    .all()
)

    board = {
        "Open": [],
        "In Progress": [],
        "Under Review": [],
        "Closed": []
    }
    for case, investigator_name in cases:

        board[case.status].append({
            "id": case.id,
            "case_id": case.case_id,
            "title": case.title,
            "investigator_name": investigator_name,
            "priority": case.priority,
            "status": case.status,
            "created_at": case.created_at
        })

    return board


def get_case_details(db: Session, case_id: int):

    result = (
        db.query(Case)
        .outerjoin(User, Case.investigator_id == User.id)
        .add_columns(User.full_name)
        .filter(Case.id == case_id)
        .first()
    )

    if not result:
        return None

    case, investigator_name = result

    return {
        "id": case.id,
        "case_id": case.case_id,
        "title": case.title,
        "description": case.description,
        "priority": case.priority,
        "status": case.status,
        "created_by": case.created_by,
        "created_at": case.created_at,
        "updated_at": case.updated_at,
        "investigator_id": case.investigator_id,
        "investigator_name": investigator_name
    }

def assign_investigator(db: Session, case_id: int, investigator_id: int):

    case = db.query(Case).filter(Case.id == case_id).first()

    if not case:
        return None

    investigator = (
        db.query(User)
        .filter(User.id == investigator_id)
        .first()
    )

    if not investigator:
        return "INVESTIGATOR_NOT_FOUND"

    case.investigator_id = investigator_id

    db.commit()
    db.refresh(case)

    create_timeline_event(
    db=db,
    case_id=case.id,
    event=f"Investigator assigned to {investigator.full_name}",
    performed_by=1,
    performed_by_role="Administrator"
    )

    create_notification(
    db=db,
    title="Investigator Assigned",
    message=f"{investigator.full_name} has been assigned to case {case.case_id}.",
    notification_type="case"
    )

    return {
        "message": "Investigator assigned successfully",
        "case_id": case.case_id,
        "investigator_name": investigator.full_name
    }

    