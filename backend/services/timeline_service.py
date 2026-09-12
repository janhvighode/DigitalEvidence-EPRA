from datetime import datetime, timezone
from typing import List, Optional, Dict, Any
from sqlalchemy.orm import Session

from models.case_timeline import CaseTimeline
from models.custody_log import CustodyLog
from models.activity_log import ActivityLog


def create_timeline_event(
    db: Session,
    case_id: int,
    event: str,
    performed_by: int,
    performed_by_role: str
):
    """
    Legacy helper for recording case timeline events in case_timeline table.
    Preserved for backward compatibility with Administrator dashboard.
    """
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


class TimelineService:

    @staticmethod
    def build_case_timeline(db: Session, case_id: str) -> List[Dict[str, Any]]:
        """
        Reconstruct a chronological timeline strictly from real stored events.
        Uses `event_reference` to link related custody and activity records
        so that one underlying action is never duplicated in the combined timeline.
        Preserves true occurrence timestamps with deterministic tie-breaking.
        """
        clean_case_id = str(case_id).strip()
        raw_events = []

        # 1. Custody Logs
        custody_entries = db.query(CustodyLog).filter(
            CustodyLog.case_id == clean_case_id
        ).all()

        for c in custody_entries:
            dt = c.timestamp
            if dt and dt.tzinfo is None:
                dt = dt.replace(tzinfo=timezone.utc)

            raw_events.append({
                "dt": dt,
                "event_ref": c.event_reference,
                "table": "custody",
                "id": c.id,
                "evidence_id": c.evidence_id,
                "action": c.action,
                "actor": c.investigator_name,
                "result": c.result,
                "remarks": c.remarks,
                "transfer_sender": c.transfer_sender,
                "transfer_recipient": c.transfer_recipient
            })

        # 2. Activity Logs
        activity_entries = db.query(ActivityLog).filter(
            ActivityLog.case_id == clean_case_id
        ).all()

        for a in activity_entries:
            dt = a.timestamp
            if dt and dt.tzinfo is None:
                dt = dt.replace(tzinfo=timezone.utc)

            raw_events.append({
                "dt": dt,
                "event_ref": a.event_reference,
                "table": "activity",
                "id": a.id,
                "evidence_id": a.external_evidence_id or (str(a.evidence_id) if a.evidence_id is not None else None),
                "action": a.action or a.activity,
                "actor": a.investigator_name,
                "result": a.outcome,
                "remarks": a.details or a.activity
            })

        # Group events by event_reference if available, otherwise by (dt, action, evidence_id)
        grouped_events: Dict[str, Dict[str, Any]] = {}

        for ev in raw_events:
            if ev.get("event_ref"):
                group_key = f"REF_{ev['event_ref']}"
            else:
                group_key = f"FALLBACK_{ev['dt'].isoformat() if ev['dt'] else 'none'}_{ev['action']}_{ev['evidence_id']}"

            if group_key not in grouped_events:
                grouped_events[group_key] = {
                    "dt": ev["dt"],
                    "event_ref": ev.get("event_ref"),
                    "evidence_id": ev.get("evidence_id"),
                    "action": ev["action"],
                    "actor": ev["actor"],
                    "result": ev.get("result", "SUCCESS"),
                    "remarks_list": [ev["remarks"]] if ev.get("remarks") else [],
                    "tables": {ev["table"]},
                    "sort_id": f"{ev['table']}_{ev['id']}"
                }
            else:
                grp = grouped_events[group_key]
                grp["tables"].add(ev["table"])
                if ev.get("remarks") and ev["remarks"] not in grp["remarks_list"]:
                    grp["remarks_list"].append(ev["remarks"])
                # Prefer earlier dt if any slight difference
                if ev["dt"] and (grp["dt"] is None or ev["dt"] < grp["dt"]):
                    grp["dt"] = ev["dt"]

        # Convert groups to sorted timeline items
        timeline_list = []
        for key, grp in grouped_events.items():
            dt = grp["dt"] or datetime.now(timezone.utc)
            action = grp["action"]
            ev_id = grp["evidence_id"]
            actor = grp["actor"]

            # Readable summary description
            tables_str = "+".join(sorted(grp["tables"]))
            remarks = " | ".join(grp["remarks_list"])

            if action == "EVIDENCE_UPLOADED":
                desc = f"Evidence #{ev_id} uploaded by {actor}. {remarks}"
            elif action == "TRANSFER_INITIATED":
                desc = f"Evidence #{ev_id} transfer initiated by {actor}. {remarks}"
            elif action == "TRANSFER_RECEIVED":
                desc = f"Evidence #{ev_id} transfer received by {actor}. {remarks}"
            elif "HASH" in action or "INTEGRITY" in action:
                desc = f"Evidence #{ev_id} cryptographic hash verification recorded. {remarks}"
            elif action == "REPORT_GENERATED":
                desc = f"Formal case report generated by {actor}. {remarks}"
            elif action == "ACCESSED_FOR_ANALYSIS":
                desc = f"Evidence #{ev_id} accessed for analysis by {actor}. {remarks}"
            elif action == "CUSTODY_INFO_UPDATED":
                desc = f"Custody information for evidence #{ev_id} updated by {actor}. {remarks}"
            else:
                desc = f"Action '{action}' on evidence #{ev_id or 'N/A'} by {actor}. {remarks}"

            timeline_list.append({
                "timestamp_dt": dt,
                "timestamp": dt.isoformat(),
                "source": f"AUDIT_TRAIL ({tables_str})",
                "event_type": action,
                "description": desc,
                "evidence_id": ev_id,
                "actor": actor,
                "event_reference": grp.get("event_ref"),
                "sort_id": grp["sort_id"]
            })

        # Deterministic sorting: occurrence timestamp ascending, then action, then sort_id
        timeline_list.sort(
            key=lambda x: (x["timestamp_dt"], x["event_type"], x["sort_id"])
        )

        # Number steps 1..N
        ordered_timeline = []
        for idx, item in enumerate(timeline_list, start=1):
            item_copy = dict(item)
            item_copy["step"] = idx
            del item_copy["timestamp_dt"]
            ordered_timeline.append(item_copy)

        return ordered_timeline