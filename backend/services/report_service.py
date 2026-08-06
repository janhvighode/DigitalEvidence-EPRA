from sqlalchemy.orm import Session
from sqlalchemy import or_

from models.case import Case
from models.user import User
from models.case_timeline import CaseTimeline


# ============================================
# Get All Completed Reports
# ============================================

def get_completed_reports(db: Session):

    reports = (
        db.query(Case, User.full_name)
        .join(User, Case.investigator_id == User.id)
        .filter(Case.status == "Closed")
        .all()
    )

    result = []

    for case, investigator_name in reports:

        result.append({
            "case_id": case.case_id,
            "title": case.title,
            "investigator_name": investigator_name,
            "priority": case.priority,
            "status": case.status,
            "created_at": case.created_at
        })

    return result


# ============================================
# Get Single Report Details
# ============================================

def get_report_details(db: Session, case_id: int):

    report = (
        db.query(Case, User.full_name)
        .join(User, Case.investigator_id == User.id)
        .filter(Case.id == case_id)
        .first()
    )

    if report is None:
        return None

    case, investigator_name = report

    timeline = (
        db.query(CaseTimeline)
        .filter(CaseTimeline.case_id == case.id)
        .order_by(CaseTimeline.created_at.asc())
        .all()
    )

    timeline_data = []

    for event in timeline:

        timeline_data.append({

            "event": event.event,

            "performed_by_role": event.performed_by_role,

            "created_at": event.created_at

        })

    return {

        "case_id": case.case_id,

        "title": case.title,

        "description": case.description,

        "investigator_name": investigator_name,

        "priority": case.priority,

        "status": case.status,

        "created_at": case.created_at,

        "updated_at": case.updated_at,

        "timeline": timeline_data,

        # Future Integration
        "epra_score": None,
        "cbir_match": None,
        "evidence_count": None,
        "chain_of_custody": None,
        "report_generated": False

    }


# ============================================
# Search Reports
# ============================================

def search_reports(db: Session, keyword: str):

    reports = (
        db.query(Case, User.full_name)
        .join(User, Case.investigator_id == User.id)
        .filter(
            or_(
                Case.title.ilike(f"%{keyword}%"),
                Case.case_id.ilike(f"%{keyword}%")
            )
        )
        .all()
    )

    result = []

    for case, investigator_name in reports:

        result.append({

            "case_id": case.case_id,

            "title": case.title,

            "investigator_name": investigator_name,

            "priority": case.priority,

            "status": case.status,

            "created_at": case.created_at

        })

    return result