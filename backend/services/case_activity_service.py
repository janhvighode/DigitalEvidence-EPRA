
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

    # Notification for investigator + same branch admin
    create_notification(
        db=db,
        title="Investigator Assigned",
        message=(
            f"You have been assigned to case "
            f"{case.case_id}."
        ),
        notification_type="case",
        user_id=investigator.id,
        cyber_cell_id=current_user.cyber_cell_id
    )

    return {
        "message": "Investigator assigned successfully",
        "case_id": case.case_id,
        "investigator_name": investigator.full_name
    }