from datetime import datetime, timezone
from typing import Optional, List, Dict, Any
from sqlalchemy.orm import Session
from app.models.activity_log import ActivityLog


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

    _log_activity = log_activity

    @staticmethod
    def get_case_activity(db: Session, case_id: str) -> List[ActivityLog]:
        """
        Retrieve all activity logs for a specific case.
        """
        return db.query(ActivityLog).filter(
            ActivityLog.case_id == case_id
        ).order_by(ActivityLog.timestamp.asc(), ActivityLog.id.asc()).all()

    @staticmethod
    def generate_activity_log(
        investigator_name: str,
        events: list
    ) -> list:
        """
        Backward-compatible helper for legacy test/demo scripts.
        Labels supplied event strings clearly and preserves provided timestamps if structured,
        rather than inventing falsified timestamps.
        """
        logs = []
        for event in events:
            if isinstance(event, dict):
                logs.append({
                    "investigator": event.get("investigator", investigator_name),
                    "activity": event.get("activity", "Activity"),
                    "time": event.get("time", event.get("timestamp", "Timestamp not recorded (supplied input)"))
                })
            else:
                logs.append({
                    "investigator": investigator_name,
                    "activity": str(event),
                    "time": "Supplied demo string (timestamp unverified)"
                })
        return logs