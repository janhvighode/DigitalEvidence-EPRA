from sqlalchemy.orm import Session, aliased

from models.case import Case
from models.user import User
from schemas.dashboard import (
    DashboardStats,
    RecentCase,
    PrioritySummary
)


# ==========================================
# DASHBOARD STATS - BRANCH WISE
# ==========================================

def get_dashboard_stats(
    db: Session,
    current_user: User
):

    # Logged-in Admin ki branch ke users
    total_users = db.query(User).filter(
        User.cyber_cell_id == current_user.cyber_cell_id,
        User.role_id.in_([2, 3])   # Investigator + Cyber Expert
    ).count()

    # Case ki branch created_by user se identify hogi
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

    open_cases = branch_cases.filter(
        Case.status == "Open"
    ).count()

    in_progress_cases = branch_cases.filter(
        Case.status == "In Progress"
    ).count()

    under_review_cases = branch_cases.filter(
        Case.status == "Under Review"
    ).count()

    closed_cases = branch_cases.filter(
        Case.status == "Closed"
    ).count()

    high_priority = branch_cases.filter(
        Case.priority == "High"
    ).count()

    pending_analysis = branch_cases.filter(
        Case.status != "Closed"
    ).count()

    return DashboardStats(
        total_users=total_users,
        total_cases=total_cases,
        open_cases=open_cases,
        in_progress_cases=in_progress_cases,
        under_review_cases=under_review_cases,
        closed_cases=closed_cases,

        # Evidence module abhi integrate nahi hua
        evidence_files=0,

        high_priority=high_priority,
        pending_analysis=pending_analysis
    )


# ==========================================
# RECENT CASES - BRANCH WISE
# ==========================================

def get_recent_cases(
    db: Session,
    current_user: User
):

    Creator = aliased(User)

    cases = (
        db.query(Case)
        .join(
            Creator,
            Case.created_by == Creator.id
        )
        .filter(
            Creator.cyber_cell_id ==
            current_user.cyber_cell_id
        )
        .order_by(
            Case.created_at.desc()
        )
        .limit(5)
        .all()
    )

    return [
        RecentCase(
            id=case.id,
            case_id=case.case_id,
            title=case.title,
            status=case.status,
            priority=case.priority
        )
        for case in cases
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

    high = branch_cases.filter(
        Case.priority == "High"
    ).count()

    medium = branch_cases.filter(
        Case.priority == "Medium"
    ).count()

    low = branch_cases.filter(
        Case.priority == "Low"
    ).count()

    return PrioritySummary(
        high=high,
        medium=medium,
        low=low
    )