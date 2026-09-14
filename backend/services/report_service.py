from sqlalchemy.orm import Session
from sqlalchemy import or_

from models.case import Case
from models.user import User
from models.case_timeline import CaseTimeline


# ============================================
# Get All Completed Reports
# ============================================

def get_completed_reports(db: Session, current_user: User):

    creator = User.__table__.alias("creator")
    query = (
        db.query(Case, User.full_name)
        .outerjoin(User, Case.investigator_id == User.id)
        .filter(Case.status == "Closed")
    )

    if current_user.role_id == 1:
        # Administrator: scoped to cyber cell via case creator
        if current_user.cyber_cell_id is None:
            return []
        query = query.join(creator, Case.created_by == creator.c.id).filter(
            creator.c.cyber_cell_id == current_user.cyber_cell_id
        )
    elif current_user.role_id == 2:
        # Investigator: scoped to own assigned cases
        query = query.filter(Case.investigator_id == current_user.id)
    elif current_user.role_id == 3:
        # Cyber Expert: scoped to own assigned cases
        query = query.filter(Case.cyber_expert_id == current_user.id)
    else:
        return []

    reports = query.all()

    result = []

    for case, investigator_name in reports:

        result.append({
            "case_id": case.case_id,
            "title": case.title,
            "investigator_name": investigator_name or "Unassigned",
            "priority": case.priority,
            "status": case.status,
            "created_at": case.created_at
        })

    return result


# ============================================
# Get Single Report Details
# ============================================

def get_report_details(db: Session, case_id: int, current_user: User):

    creator = User.__table__.alias("creator")
    query = (
        db.query(Case, User.full_name)
        .outerjoin(User, Case.investigator_id == User.id)
        .filter(Case.id == case_id)
    )

    if current_user.role_id == 1:
        if current_user.cyber_cell_id is None:
            return None
        query = query.join(creator, Case.created_by == creator.c.id).filter(
            creator.c.cyber_cell_id == current_user.cyber_cell_id
        )
    elif current_user.role_id == 2:
        query = query.filter(Case.investigator_id == current_user.id)
    elif current_user.role_id == 3:
        query = query.filter(Case.cyber_expert_id == current_user.id)
    else:
        return None

    report = query.first()

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

        "investigator_name": investigator_name or "Unassigned",

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

def search_reports(db: Session, keyword: str, current_user: User):

    creator = User.__table__.alias("creator")
    query = (
        db.query(Case, User.full_name)
        .outerjoin(User, Case.investigator_id == User.id)
        .filter(
            or_(
                Case.title.ilike(f"%{keyword}%"),
                Case.case_id.ilike(f"%{keyword}%")
            )
        )
    )

    if current_user.role_id == 1:
        if current_user.cyber_cell_id is None:
            return []
        query = query.join(creator, Case.created_by == creator.c.id).filter(
            creator.c.cyber_cell_id == current_user.cyber_cell_id
        )
    elif current_user.role_id == 2:
        query = query.filter(Case.investigator_id == current_user.id)
    elif current_user.role_id == 3:
        query = query.filter(Case.cyber_expert_id == current_user.id)
    else:
        return []

    reports = query.all()

    result = []

    for case, investigator_name in reports:

        result.append({

            "case_id": case.case_id,

            "title": case.title,

            "investigator_name": investigator_name or "Unassigned",

            "priority": case.priority,

            "status": case.status,

            "created_at": case.created_at

        })

    return result