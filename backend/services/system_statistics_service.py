from sqlalchemy.orm import Session
from sqlalchemy import func

from models.case import Case
from models.user import User
from models.role import Role


# ==========================
# EPRA ANALYTICS
# ==========================
def get_epra_statistics(db: Session):

    total_cases = db.query(Case).count()

    high = db.query(Case).filter(Case.priority == "High").count()

    medium = db.query(Case).filter(Case.priority == "Medium").count()

    low = db.query(Case).filter(Case.priority == "Low").count()

    pending = db.query(Case).filter(Case.status != "Closed").count()

    overall_health = 86.0

    average_score = 0.78
    highest_score = 0.98
    lowest_score = 0.22

    return {
        "overall_health": overall_health,

        "total_evidence": total_cases,

        "high_priority": high,
        "medium_priority": medium,
        "low_priority": low,
        "pending_analysis": pending,

        "average_epra_score": average_score,
        "highest_score": highest_score,
        "lowest_score": lowest_score,
    }


# ==========================
# CBIR STATISTICS
# ==========================
def get_cbir_statistics(db: Session):

    total_images = 350
    matched = 322
    failed = 28

    match_rate = round((matched / total_images) * 100, 2)

    return {
        "total_images": total_images,
        "matched_images": matched,
        "failed_matches": failed,
        "match_rate": match_rate
    }


# ==========================
# INVESTIGATOR PERFORMANCE
# ==========================
def get_investigator_performance(db: Session):

    investigators = (
        db.query(User)
        .join(Role, User.role_id == Role.id)
        .filter(Role.role_name == "Investigator")
        .all()
    )

    result = []

    for investigator in investigators:

        assigned = db.query(Case).filter(
            Case.investigator_id == investigator.id
        ).count()

        completed = db.query(Case).filter(
            Case.investigator_id == investigator.id,
            Case.status == "Closed"
        ).count()

        active = assigned - completed

        percentage = (
            round((completed / assigned) * 100, 2)
            if assigned > 0 else 0
        )

        result.append({

            "investigator_name": investigator.full_name,

            "assigned_cases": assigned,

            "completed_cases": completed,

            "active_cases": active,

            "completion_percentage": percentage

        })

    return result


# ==========================
# CASE TREND
# ==========================
def get_case_progress_trend(db: Session):

    return [

        {
            "month": "Jan",
            "created_cases": 18,
            "closed_cases": 14
        },

        {
            "month": "Feb",
            "created_cases": 24,
            "closed_cases": 18
        },

        {
            "month": "Mar",
            "created_cases": 20,
            "closed_cases": 17
        },

        {
            "month": "Apr",
            "created_cases": 28,
            "closed_cases": 23
        },

        {
            "month": "May",
            "created_cases": 35,
            "closed_cases": 30
        }

    ]


# ==========================
# PRIORITY ANALYSIS
# ==========================
def get_priority_analysis(db: Session):

    return {

        "high_priority": db.query(Case).filter(
            Case.priority == "High"
        ).count(),

        "medium_priority": db.query(Case).filter(
            Case.priority == "Medium"
        ).count(),

        "low_priority": db.query(Case).filter(
            Case.priority == "Low"
        ).count()

    }