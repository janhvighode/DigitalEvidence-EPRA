from datetime import datetime, timezone
from typing import List, Optional, Dict, Any
from sqlalchemy.orm import Session

from app.models.custody_log import CustodyLog
from app.models.activity_log import ActivityLog
from app.models.integrity_log import IntegrityVerificationLog
from app.models.evidence_record import EvidenceRecord
from app.models.report_record import ReportRecord


class TimelineService:

    @staticmethod
    def build_case_timeline(db: Session, case_id: str) -> List[Dict[str, Any]]:
        """
        Reconstruct a chronological timeline strictly from real stored events.
        Uses `event_reference` to link related custody, activity, and integrity records
        so that one underlying action is never duplicated in the combined timeline.
        Preserves true occurrence timestamps with deterministic tie-breaking.
        """
        clean_case_id = case_id.strip()

        # Gather events across tables
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

        # 3. Integrity Verification Logs
        integrity_entries = db.query(IntegrityVerificationLog).filter(
            IntegrityVerificationLog.case_id == clean_case_id
        ).all()

        for i in integrity_entries:
            dt = i.verified_at
            if dt and dt.tzinfo is None:
                dt = dt.replace(tzinfo=timezone.utc)

            raw_events.append({
                "dt": dt,
                "event_ref": i.event_reference,
                "table": "integrity",
                "id": i.id,
                "evidence_id": i.evidence_id,
                "action": f"INTEGRITY_CHECK_{i.outcome}",
                "actor": i.actor,
                "result": i.outcome,
                "remarks": f"Outcome: {i.outcome}. Baseline: {i.baseline_hash[:16] if i.baseline_hash else 'None'}... Error: {i.error_reason or 'None'}"
            })

        # 4. Report Records
        report_entries = db.query(ReportRecord).filter(
            ReportRecord.case_id == clean_case_id
        ).all()

        for r in report_entries:
            dt = r.generated_at
            if dt and dt.tzinfo is None:
                dt = dt.replace(tzinfo=timezone.utc)

            raw_events.append({
                "dt": dt,
                "event_ref": r.event_reference,
                "table": "report",
                "id": r.id,
                "evidence_id": None,
                "action": "REPORT_GENERATED",
                "actor": r.investigator_name,
                "result": "SUCCESS",
                "remarks": f"Generated PDF report {r.file_name} (ID: {r.id})"
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
            elif "INTEGRITY" in action:
                desc = f"Evidence #{ev_id} integrity verification performed. {remarks}"
            elif action == "REPORT_GENERATED":
                desc = f"Formal case report generated by {actor}. {remarks}"
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

    @staticmethod
    def generate_timeline(
        case_id: str,
        events: Optional[list] = None,
        db: Optional[Session] = None
    ) -> List[Dict[str, Any]]:
        """
        Produce a timeline. If DB session is provided, builds chronological deduplicated timeline.
        If only legacy event strings are supplied, preserves their sequence without
        falsifying occurrence times with datetime.now().
        """
        if db is not None:
            db_timeline = TimelineService.build_case_timeline(db, case_id)
            if db_timeline:
                return db_timeline

        timeline = []
        if events:
            for index, event in enumerate(events, start=1):
                if isinstance(event, dict):
                    timeline.append({
                        "step": index,
                        "case_id": case_id,
                        "event": event.get("event", "Event"),
                        "timestamp": event.get("timestamp", "Supplied event string (occurrence time unverified)"),
                        "source": event.get("source", "SUPPLIED_INPUT")
                    })
                else:
                    timeline.append({
                        "step": index,
                        "case_id": case_id,
                        "event": str(event),
                        "timestamp": "Supplied demo string (occurrence time unverified)",
                        "source": "SUPPLIED_INPUT"
                    })
        return timeline