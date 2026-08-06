from sqlalchemy.orm import Session

from models.case_timeline import CaseTimeline


def create_timeline_event(
    db: Session,
    case_id: int,
    event: str,
    performed_by: int,
    performed_by_role: str
):

    timeline = CaseTimeline(

        case_id=case_id,

        event=event,

        performed_by=performed_by,

        performed_by_role=performed_by_role

    )

    db.add(timeline)

    db.commit()

    db.refresh(timeline)

    return timeline