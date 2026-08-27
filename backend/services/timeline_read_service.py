from sqlalchemy.orm import Session

from models.case_timeline import CaseTimeline


def get_case_timeline(db: Session, case_id: int):

    timeline = (
        db.query(CaseTimeline)
        .filter(CaseTimeline.case_id == case_id)
        .order_by(CaseTimeline.created_at.asc())
        .all()
    )

    return timeline