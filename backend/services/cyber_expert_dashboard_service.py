from sqlalchemy.orm import Session

from models.case import Case
from models.user import User


# ==========================================
# CYBER EXPERT DASHBOARD STATS
# ==========================================

def get_cyber_expert_dashboard_stats(
    db: Session,
    current_user: User
):

    cases = db.query(Case).filter(
        Case.cyber_expert_id == current_user.id
    )

    assigned_cases = cases.count()

    # Open = Pending
    pending_cases = cases.filter(
        Case.status == "Open"
    ).count()

    # In Progress + Under Review = Under Analysis
    under_analysis = cases.filter(
        Case.status.in_([
            "In Progress",
            "Under Review"
        ])
    ).count()

    # Closed = Completed
    completed_cases = cases.filter(
        Case.status == "Closed"
    ).count()

    return {
        "assigned_cases": assigned_cases,
        "pending_cases": pending_cases,
        "under_analysis": under_analysis,
        "completed_cases": completed_cases
    }


# ==========================================
# RECENT / ASSIGNED CASES
# ==========================================

def get_cyber_expert_cases(
    db: Session,
    current_user: User
):

    cases = (
        db.query(Case)
        .filter(
            Case.cyber_expert_id ==
            current_user.id
        )
        .order_by(
            Case.updated_at.desc()
        )
        .all()
    )

    return cases


# ==========================================
# CASE STATUS CHART
# ==========================================

def get_cyber_expert_case_status(
    db: Session,
    current_user: User
):

    cases = db.query(Case).filter(
        Case.cyber_expert_id == current_user.id
    )

    pending = cases.filter(
        Case.status == "Open"
    ).count()

    under_analysis = cases.filter(
        Case.status.in_([
            "In Progress",
            "Under Review"
        ])
    ).count()

    completed = cases.filter(
        Case.status == "Closed"
    ).count()

    return {
        "pending": pending,
        "under_analysis": under_analysis,
        "completed": completed
    }