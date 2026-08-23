from sqlalchemy.orm import Session, aliased

from models.case import Case
from models.user import User

from schemas.dashboard import (
    DashboardStats,
    RecentCase,
    PrioritySummary
)

from services.admin_service import get_pending_registrations


# ==========================================
# DASHBOARD STATS
# ==========================================

def get_dashboard_stats(
    db: Session,
    current_user: User
):

    # ======================================
    # TOTAL USERS - BRANCH WISE
    # ======================================

    total_users = (
        db.query(User)
        .filter(
            User.cyber_cell_id == current_user.cyber_cell_id,
            User.role_id.in_([2, 3])
        )
        .count()
    )


    # ======================================
    # CASES - BRANCH WISE
    # ======================================

    Creator = aliased(User)

    branch_cases = (
        db.query(Case)
        .join(
            Creator,
            Case.created_by == Creator.id
        )
        .filter(
            Creator.cyber_cell_id ==
            current_user.cyber_cell_id
        )
    )


    total_cases = branch_cases.count()


    open_cases = (
        branch_cases
        .filter(
            Case.status == "Open"
        )
        .count()
    )


    in_progress_cases = (
        branch_cases
        .filter(
            Case.status == "In Progress"
        )
        .count()
    )


    under_review_cases = (
        branch_cases
        .filter(
            Case.status == "Under Review"
        )
        .count()
    )


    closed_cases = (
        branch_cases
        .filter(
            Case.status == "Closed"
        )
        .count()
    )


    # ======================================
    # PENDING REGISTRATION REQUESTS
    # ROLE-BASED APPROVAL LOGIC
    # ======================================

    pending_requests = get_pending_registrations(
        db,
        current_user
    )

    pending_registration_requests = len(
        pending_requests
    )


    # ======================================
    # RETURN DASHBOARD CARDS
    # ======================================

    return DashboardStats(
        total_cases=total_cases,

        pending_registration_requests=
        pending_registration_requests,

        total_users=total_users,

        open_cases=open_cases,

        in_progress_cases=in_progress_cases,

        under_review_cases=
        under_review_cases,

        closed_cases=closed_cases
    )


# ==========================================
# RECENT CASES / CASE DETAILS
# BRANCH WISE
# ==========================================

def get_recent_cases(
    db: Session,
    current_user: User
):

    Creator = aliased(User)
    Investigator = aliased(User)

    cases = (
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
            Case.investigator_id ==
            Investigator.id
        )
        .filter(
            Creator.cyber_cell_id ==
            current_user.cyber_cell_id
        )
        .order_by(
            Case.updated_at.desc()
        )
        .limit(10)
        .all()
    )


    return [
        RecentCase(
            id=case.id,

            case_id=case.case_id,

            title=case.title,

            status=case.status,

            priority=case.priority,

            investigator_name=
            investigator_name,

            updated_at=(
                case.updated_at.isoformat()
                if case.updated_at
                else None
            )
        )

        for case, investigator_name in cases
    ]


# ==========================================
# PRIORITY SUMMARY - BRANCH WISE
# ==========================================

def get_priority_summary(
    db: Session,
    current_user: User
):

    Creator = aliased(User)

    branch_cases = (
        db.query(Case)
        .join(
            Creator,
            Case.created_by == Creator.id
        )
        .filter(
            Creator.cyber_cell_id ==
            current_user.cyber_cell_id
        )
    )


    high = (
        branch_cases
        .filter(
            Case.priority == "High"
        )
        .count()
    )


    medium = (
        branch_cases
        .filter(
            Case.priority == "Medium"
        )
        .count()
    )


    low = (
        branch_cases
        .filter(
            Case.priority == "Low"
        )
        .count()
    )


    return PrioritySummary(
        high=high,
        medium=medium,
        low=low
    )