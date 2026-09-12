from datetime import datetime, timezone
from typing import Optional, Any
from sqlalchemy.orm import Session
from models.activity_log import ActivityLog


class ActivityService:

    @staticmethod
    def log_activity(
        db: Session,
        investigator_name: str,
        activity: str,
        case_id: Optional[str] = None,
        evidence_id: Optional[Any] = None,
        external_evidence_id: Optional[str] = None,
        actor_id: Optional[str] = None,
        action: Optional[str] = None,
        outcome: str = "SUCCESS",
        details: Optional[str] = None,
        ip_address: Optional[str] = None,
        timestamp: Optional[datetime] = None
    ) -> ActivityLog:
        """
        Persist an authentic investigator activity log entry.
        Preserves external string evidence IDs rather than discarding or storing None.
        """
        if timestamp is None:
            timestamp = datetime.now(timezone.utc)

        str_ev_id = external_evidence_id or (str(evidence_id) if evidence_id is not None else None)
        num_ev_id = int(evidence_id) if isinstance(evidence_id, int) or (isinstance(evidence_id, str) and evidence_id.isdigit()) else None

        log = ActivityLog(
            case_id=case_id,
            evidence_id=num_ev_id,
            external_evidence_id=str_ev_id,
            actor_id=actor_id,
            action=action or activity,
            investigator_name=investigator_name or "Unknown Investigator",
            activity=activity,
            outcome=outcome,
            details=details,
            ip_address=ip_address,
            timestamp=timestamp
        )

        db.add(log)
        db.commit()
        db.refresh(log)
        return log
