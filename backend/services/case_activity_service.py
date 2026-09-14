
from sqlalchemy.orm import Session, aliased

from models.case import Case
from models.user import User

from services.timeline_service import create_timeline_event
from services.notification_service import create_notification


# ==========================================
# CASE BOARD
# ==========================================

def get_case_board(
    db: Session,
    current_user: User
):

    board = {
        "Open": [],
        "In Progress": [],
        "Under Review": [],
        "Closed": []
    }

    # ==========================================
    # ADMINISTRATOR - OWN BRANCH CASES
    # ==========================================

    if current_user.role_id == 1:

        Creator = aliased(User)
        Investigator = aliased(User)

        results = (
            db.query(
                Case,
                Investigator.full_name.label(
                    "investigator_name"
                )
            )
            .join(
                Creator,
                Case.created_by == Creator.id
            )
            .outerjoin(
                Investigator,
                Case.investigator_id == Investigator.id
            )
            .filter(
                Creator.cyber_cell_id ==
                current_user.cyber_cell_id
            )
            .order_by(
                Case.updated_at.desc()
            )
            .all()
        )

    # ==========================================
    # INVESTIGATOR - ONLY OWN ASSIGNED CASES
    # ==========================================

    elif current_user.role_id == 2:

        Investigator = aliased(User)

        results = (
            db.query(
                Case,
                Investigator.full_name.label(
                    "investigator_name"
                )
            )
            .outerjoin(
                Investigator,
                Case.investigator_id == Investigator.id
            )
            .filter(
                Case.investigator_id ==
                current_user.id
            )
            .order_by(
                Case.updated_at.desc()
            )
            .all()
        )

    # ==========================================
    # OTHER ROLES
    # ==========================================

    else:
        return board


    # ==========================================
    # BUILD BOARD
    # ==========================================

    for case, investigator_name in results:

        case_data = {
            "id": case.id,
            "case_id": case.case_id,
            "title": case.title,
            "investigator_name": investigator_name,
            "priority": case.priority,
            "status": case.status,
            "created_at": case.created_at,
            "updated_at": case.updated_at
        }

        if case.status in board:
            board[case.status].append(
                case_data
            )


    return board

# ==========================================
# CASE DETAILS
# ==========================================

def get_case_details(
    db: Session,
    case_id: int,
    current_user: User
):

    query = (
        db.query(Case)
        .outerjoin(
            User,
            Case.investigator_id == User.id
        )
        .add_columns(User.full_name)
        .filter(
            Case.id == case_id
        )
    )

    # ADMINISTRATOR
    if current_user.role_id == 1:

        creator = User.__table__.alias("creator")

        query = (
            db.query(Case)
            .outerjoin(
                User,
                Case.investigator_id == User.id
            )
            .join(
                creator,
                Case.created_by == creator.c.id
            )
            .filter(
                Case.id == case_id,
                creator.c.cyber_cell_id ==
                current_user.cyber_cell_id
            )
            .add_columns(User.full_name)
        )

    # INVESTIGATOR
    elif current_user.role_id == 2:

        query = query.filter(
            Case.investigator_id ==
            current_user.id
        )

    result = query.first()

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


# ==========================================
# ASSIGN INVESTIGATOR
# ==========================================

def assign_investigator(
    db: Session,
    case_id: int,
    investigator_id: int,
    current_user: User
):

    # Only Administrator
    if current_user.role_id != 1:
        return "FORBIDDEN"

    # Case must belong to administrator's branch
    creator = User.__table__.alias("creator")

    case = (
        db.query(Case)
        .join(
            creator,
            Case.created_by == creator.c.id
        )
        .filter(
            Case.id == case_id,
            creator.c.cyber_cell_id ==
            current_user.cyber_cell_id
        )
        .first()
    )

    if not case:
        return None

    # Investigator must:
    # role = Investigator
    # same branch
    # active
    investigator = (
        db.query(User)
        .filter(
            User.id == investigator_id,
            User.role_id == 2,
            User.cyber_cell_id ==
            current_user.cyber_cell_id,
            User.is_active == True
        )
        .first()
    )

    if not investigator:
        return "INVESTIGATOR_NOT_FOUND"

    already_assigned = (case.investigator_id == investigator.id)
    case.investigator_id = investigator.id

    db.commit()
    db.refresh(case)

    # Correct current admin instead of hardcoded ID 1
    create_timeline_event(
        db=db,
        case_id=case.id,
        event=f"Investigator assigned to {investigator.full_name}",
        performed_by=current_user.id,
        performed_by_role="Administrator"
    )

    if not already_assigned:
        # Strictly personal notification for investigator only (no branch leakage)
        create_notification(
            db=db,
            title="Case Assigned",
            message=f"You have been assigned to case {case.case_id}.",
            notification_type="CASE_ASSIGNMENT",
            user_id=investigator.id,
            cyber_cell_id=None
        )

        # If a Cyber Expert is already assigned, notify them of team addition
        if case.cyber_expert_id:
            create_notification(
                db=db,
                title="Case Team Update",
                message=f"Investigator {investigator.full_name} has been assigned to case {case.case_id}.",
                notification_type="CASE_TEAM_UPDATE",
                user_id=case.cyber_expert_id,
                cyber_cell_id=None
            )

    return {
        "message": "Investigator assigned successfully",
        "case_id": case.case_id,
        "investigator_name": investigator.full_name
    }


def assign_cyber_expert(
    db: Session,
    case_id: int,
    cyber_expert_id: int,
    current_user: User
):

    # Only Administrator can assign Cyber Expert
    if current_user.role_id != 1:
        return "FORBIDDEN"

    creator = User.__table__.alias("creator")

    # Case must belong to Administrator's branch
    case = (
        db.query(Case)
        .join(
            creator,
            Case.created_by == creator.c.id
        )
        .filter(
            Case.id == case_id,
            creator.c.cyber_cell_id ==
            current_user.cyber_cell_id
        )
        .first()
    )

    if not case:
        return None

    # Cyber Expert must be:
    # role_id = 3
    # same branch
    # active
    cyber_expert = (
        db.query(User)
        .filter(
            User.id == cyber_expert_id,
            User.role_id == 3,
            User.cyber_cell_id ==
            current_user.cyber_cell_id,
            User.is_active == True
        )
        .first()
    )

    if not cyber_expert:
        return "CYBER_EXPERT_NOT_FOUND"

    already_assigned = (case.cyber_expert_id == cyber_expert.id)
    case.cyber_expert_id = cyber_expert.id

    db.commit()
    db.refresh(case)

    create_timeline_event(
        db=db,
        case_id=case.id,
        event=f"Cyber Expert assigned to {cyber_expert.full_name}",
        performed_by=current_user.id,
        performed_by_role="Administrator"
    )

    if not already_assigned:
        create_notification(
            db=db,
            title="Case Assigned",
            message=f"You have been assigned to case {case.case_id}.",
            notification_type="CASE_ASSIGNMENT",
            user_id=cyber_expert.id,
            cyber_cell_id=None
        )

        # If an Investigator is already assigned, notify them of team update
        if case.investigator_id:
            create_notification(
                db=db,
                title="Case Team Update",
                message=f"Cyber Expert {cyber_expert.full_name} has been assigned to case {case.case_id}.",
                notification_type="CASE_TEAM_UPDATE",
                user_id=case.investigator_id,
                cyber_cell_id=None
            )

    return {
        "message": "Cyber Expert assigned successfully",
        "case_id": case.case_id,
        "cyber_expert_name": cyber_expert.full_name
    }


# ==========================================
# UPDATE CASE STATUS
# ==========================================

def update_case_status(
    db: Session,
    case_id: int,
    new_status: str,
    current_user: User
):
    ALLOWED_STATUSES = ["Open", "In Progress", "Under Review", "Closed"]
    matched_status = None
    for s in ALLOWED_STATUSES:
        if s.lower() == new_status.strip().lower():
            matched_status = s
            break

    if not matched_status:
        return "INVALID_STATUS"

    creator = User.__table__.alias("creator")

    # Authorize access: Admin in same cyber cell, assigned Investigator, or assigned Cyber Expert
    if current_user.role_id == 1:
        case = (
            db.query(Case)
            .join(creator, Case.created_by == creator.c.id)
            .filter(
                Case.id == case_id,
                creator.c.cyber_cell_id == current_user.cyber_cell_id
            )
            .first()
        )
    elif current_user.role_id == 2:
        case = db.query(Case).filter(Case.id == case_id, Case.investigator_id == current_user.id).first()
    elif current_user.role_id == 3:
        case = db.query(Case).filter(Case.id == case_id, Case.cyber_expert_id == current_user.id).first()
    else:
        case = None

    if not case:
        return None

    previous_status = case.status
    if previous_status == matched_status:
        # Status has not changed: deduplication, do not create duplicate notifications or timeline events
        return {
            "message": "Case status unchanged",
            "case_id": case.case_id,
            "previous_status": previous_status,
            "current_status": case.status
        }

    case.status = matched_status
    db.commit()
    db.refresh(case)

    # Timeline event
    create_timeline_event(
        db=db,
        case_id=case.id,
        event=f"Case status changed from {previous_status} to {matched_status}",
        performed_by=current_user.id,
        performed_by_role="Administrator" if current_user.role_id == 1 else ("Investigator" if current_user.role_id == 2 else "Cyber Expert")
    )

    # Notify assigned Investigator
    if case.investigator_id and case.investigator_id != current_user.id:
        create_notification(
            db=db,
            title="Case Status Updated",
            message=f"Case {case.case_id} status changed from {previous_status} to {matched_status}.",
            notification_type="CASE_STATUS",
            user_id=case.investigator_id,
            cyber_cell_id=None
        )

    # Notify assigned Cyber Expert
    if case.cyber_expert_id and case.cyber_expert_id != current_user.id:
        create_notification(
            db=db,
            title="Case Status Updated",
            message=f"Case {case.case_id} status changed from {previous_status} to {matched_status}.",
            notification_type="CASE_STATUS",
            user_id=case.cyber_expert_id,
            cyber_cell_id=None
        )

    # Admin only for major milestones: UNDER REVIEW, CLOSED
    if matched_status in ["Under Review", "Closed"]:
        case_creator = db.query(User).filter(User.id == case.created_by).first()
        cell_id = case_creator.cyber_cell_id if case_creator else current_user.cyber_cell_id
        if cell_id:
            admins = db.query(User).filter(
                User.role_id == 1,
                User.cyber_cell_id == cell_id,
                User.is_active == True
            ).all()
            for admin in admins:
                if admin.id != current_user.id:
                    create_notification(
                        db=db,
                        title=f"Case Milestone: {matched_status}",
                        message=f"Case {case.case_id} has moved to {matched_status}.",
                        notification_type="CASE_STATUS",
                        user_id=admin.id,
                        cyber_cell_id=None
                    )

    return {
        "message": "Case status updated successfully",
        "case_id": case.case_id,
        "previous_status": previous_status,
        "current_status": case.status
    }



