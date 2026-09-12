from uuid import uuid4
from datetime import datetime, timezone
from typing import Optional, List, Dict, Any
from sqlalchemy.orm import Session
from sqlalchemy import func

from app.models.evidence_record import EvidenceRecord
from app.models.custody_log import CustodyLog
from app.models.activity_log import ActivityLog
from app.models.transfer_record import TransferRecord
from app.models.current_custody import CurrentCustodyInfo
from app.services.backend_adapter import get_backend_adapter, ExternalCustodyEvent


class CustodyService:

    @staticmethod
    def _resolve_case_id(db: Session, evidence_id: str, case_id: Optional[str] = None) -> Optional[str]:
        if case_id:
            return case_id
        clean_ev_id = str(evidence_id).strip()
        adapter = get_backend_adapter()
        ev_item = adapter.get_evidence(clean_ev_id)
        if ev_item and ev_item.case_id:
            return ev_item.case_id
        ev = db.query(EvidenceRecord).filter(
            (EvidenceRecord.external_evidence_id == clean_ev_id) |
            (EvidenceRecord.id == int(clean_ev_id) if clean_ev_id.isdigit() else False)
        ).first()
        if ev and ev.case_id:
            return ev.case_id
        return None

    @staticmethod
    def get_or_create_current_custody(db: Session, evidence_id: str, case_id: Optional[str] = None) -> CurrentCustodyInfo:
        """
        Fetch current custody info for an evidence item.
        If not yet created, initializes with null holder and null status (no invented defaults).
        """
        clean_ev_id = str(evidence_id).strip()
        info = db.query(CurrentCustodyInfo).filter(CurrentCustodyInfo.evidence_id == clean_ev_id).first()
        if not info:
            effective_case_id = CustodyService._resolve_case_id(db, clean_ev_id, case_id)

            info = CurrentCustodyInfo(
                evidence_id=clean_ev_id,
                case_id=effective_case_id,
                current_holder_id=None,
                current_holder_name=None,
                current_holder_role=None,
                department=None,
                assigned_on=None,
                last_accessed=None,
                location=None,
                remarks=None,
                custody_status=None,  # Nullable: never invent "In Analysis"
                pending_recipient_id=None,
                pending_recipient_name=None
            )
            db.add(info)
            db.commit()
            db.refresh(info)
        else:
            better_case_id = case_id
            if not better_case_id:
                adapter = get_backend_adapter()
                ev_item = adapter.get_evidence(clean_ev_id)
                if ev_item and ev_item.case_id:
                    better_case_id = ev_item.case_id

            if better_case_id and not info.case_id:
                info.case_id = better_case_id
                db.commit()
                db.refresh(info)
        return info

    @staticmethod
    def create_log(
        db: Session,
        evidence_id: str,
        investigator_name: str,
        action: str,
        remarks: Optional[str] = None,
        case_id: Optional[str] = None,
        investigator_id: Optional[str] = None,
        actor_role: Optional[str] = None,
        event_type: Optional[str] = None,
        title: Optional[str] = None,
        result: Optional[str] = "SUCCESS",
        transfer_reference: Optional[str] = None,
        transfer_sender: Optional[str] = None,
        transfer_recipient: Optional[str] = None,
        event_reference: Optional[str] = None,
        external_event_id: Optional[str] = None,
        source_reference: Optional[str] = None,
        related_reference: Optional[str] = None,
        is_system_action: bool = False,
        actor_is_unverified: bool = True,
        timestamp: Optional[datetime] = None
    ) -> Optional[CustodyLog]:
        """
        Record an authentic chain of custody handling event.
        Guarantees idempotent ingestion via external_event_id uniqueness constraint.
        """
        clean_ev_id = str(evidence_id).strip()

        # Idempotent check if external_event_id supplied
        if external_event_id:
            existing = db.query(CustodyLog).filter(CustodyLog.external_event_id == external_event_id).first()
            if existing:
                return existing

        if timestamp is None:
            timestamp = datetime.now(timezone.utc)
        elif timestamp.tzinfo is None:
            timestamp = timestamp.replace(tzinfo=timezone.utc)

        log = CustodyLog(
            evidence_id=clean_ev_id,
            case_id=case_id,
            external_event_id=external_event_id,
            event_type=event_type or action,
            title=title or action.replace("_", " ").title(),
            investigator_id=investigator_id,
            investigator_name=investigator_name,
            actor_role=actor_role,
            action=action,
            result=result,
            remarks=remarks,
            transfer_reference=transfer_reference,
            transfer_sender=transfer_sender,
            transfer_recipient=transfer_recipient,
            event_reference=event_reference,
            source_reference=source_reference,
            related_reference=related_reference,
            is_system_action=is_system_action,
            actor_is_unverified=actor_is_unverified,
            timestamp=timestamp
        )

        db.add(log)
        db.commit()
        db.refresh(log)
        return log

    @staticmethod
    def get_custody_summary(db: Session, evidence_id: str) -> Dict[str, Any]:
        """
        Evidence-specific summary cards matching Screenshot 2:
        - Total Events
        - Handlers (distinct human handlers)
        - Transfers (completed)
        - Pending Transfers
        - First Handled timestamp
        - Current Status
        """
        clean_ev_id = str(evidence_id).strip()

        # Sync external events if available
        CustodyService.sync_external_events(db, clean_ev_id)

        logs = db.query(CustodyLog).filter(
            CustodyLog.evidence_id == clean_ev_id
        ).order_by(CustodyLog.timestamp.asc()).all()

        total_events = len(logs)

        # Count distinct human handlers (exclude system actions)
        human_handlers = set()
        first_handled = None

        for l in logs:
            if not l.is_system_action and l.investigator_name:
                handler_key = f"{l.investigator_id or ''}_{l.investigator_name.strip().lower()}"
                human_handlers.add(handler_key)

            if first_handled is None and l.timestamp:
                first_handled = l.timestamp

        completed_transfers = db.query(TransferRecord).filter(
            TransferRecord.evidence_id == clean_ev_id,
            TransferRecord.status == "COMPLETED"
        ).count()

        pending_transfers = db.query(TransferRecord).filter(
            TransferRecord.evidence_id == clean_ev_id,
            TransferRecord.status == "PENDING_RECEIPT"
        ).count()

        custody_info = db.query(CurrentCustodyInfo).filter(
            CurrentCustodyInfo.evidence_id == clean_ev_id
        ).first()

        current_status = custody_info.custody_status if custody_info else None

        return {
            "evidence_id": clean_ev_id,
            "total_events": total_events,
            "handlers_count": len(human_handlers),
            "completed_transfers": completed_transfers,
            "pending_transfers": pending_transfers,
            "first_handled": first_handled.isoformat() if first_handled else None,
            "first_handled_formatted": first_handled.strftime("%d %b %Y, %I:%M %p") if first_handled else "Not Handled",
            "current_status": current_status
        }

    @staticmethod
    def get_custody_timeline(
        db: Session,
        evidence_id: str,
        event_filter: Optional[str] = "ALL"
    ) -> List[Dict[str, Any]]:
        """
        Chronological custody timeline matching Screenshot 2 with event filtering.
        """
        clean_ev_id = str(evidence_id).strip()
        CustodyService.sync_external_events(db, clean_ev_id)

        query = db.query(CustodyLog).filter(CustodyLog.evidence_id == clean_ev_id)

        filter_upper = (event_filter or "ALL").upper().strip()
        if filter_upper != "ALL":
            if filter_upper == "TRANSFERS":
                query = query.filter(CustodyLog.action.ilike("%transfer%"))
            elif filter_upper == "ACCESS":
                query = query.filter(CustodyLog.action.ilike("%access%"))
            elif filter_upper == "ANALYSIS":
                query = query.filter(CustodyLog.action.ilike("%analy%"))
            elif filter_upper == "REPORT":
                query = query.filter(CustodyLog.action.ilike("%report%"))
            elif filter_upper == "ACQUISITION":
                query = query.filter(CustodyLog.action.ilike("%acqui%"))
            elif filter_upper == "UPLOAD":
                query = query.filter(CustodyLog.action.ilike("%upload%"))
            elif filter_upper == "HASH":
                query = query.filter(CustodyLog.action.ilike("%hash%"))
            else:
                query = query.filter(CustodyLog.event_type == filter_upper)

        logs = query.order_by(CustodyLog.timestamp.asc(), CustodyLog.id.asc()).all()

        timeline_items = []
        for l in logs:
            timeline_items.append({
                "event_id": l.id,
                "external_event_id": l.external_event_id,
                "evidence_id": l.evidence_id,
                "case_id": l.case_id,
                "event_type": l.event_type or l.action,
                "title": l.title or l.action.replace("_", " ").title(),
                "description": l.remarks,
                "timestamp": l.timestamp.isoformat() if l.timestamp else None,
                "timestamp_formatted": l.timestamp.strftime("%d %b %Y, %I:%M %p") if l.timestamp else None,
                "recorded_at": l.recorded_at.isoformat() if l.recorded_at else None,
                "actor_id": l.investigator_id,
                "actor_name": l.investigator_name,
                "actor_role": l.actor_role or ("System Automated" if l.is_system_action else "Investigator"),
                "is_system_action": l.is_system_action,
                "outcome": l.result or "SUCCESS",
                "transfer_reference": l.transfer_reference,
                "related_reference": l.related_reference,
                "source_reference": l.source_reference
            })
        return timeline_items

    @staticmethod
    def get_current_custody(db: Session, evidence_id: str) -> Dict[str, Any]:
        """
        Current Custody Information card matching Screenshot 2 right panel.
        Returns actual holder, department, timestamps, or null (no invented defaults).
        """
        clean_ev_id = str(evidence_id).strip()
        info = CustodyService.get_or_create_current_custody(db, clean_ev_id)

        return {
            "evidence_id": clean_ev_id,
            "case_id": info.case_id,
            "current_holder_id": info.current_holder_id,
            "current_holder_name": info.current_holder_name,
            "current_holder_role": info.current_holder_role,
            "department": info.department,
            "assigned_on": info.assigned_on.isoformat() if info.assigned_on else None,
            "assigned_on_formatted": info.assigned_on.strftime("%d %b %Y, %I:%M %p") if info.assigned_on else None,
            "last_accessed": info.last_accessed.isoformat() if info.last_accessed else None,
            "last_accessed_formatted": info.last_accessed.strftime("%d %b %Y, %I:%M %p") if info.last_accessed else None,
            "location": info.location,
            "remarks": info.remarks,
            "custody_status": info.custody_status,
            "pending_recipient_id": info.pending_recipient_id,
            "pending_recipient_name": info.pending_recipient_name,
            "updated_at": info.updated_at.isoformat() if info.updated_at else None
        }

    @staticmethod
    def update_current_custody(
        db: Session,
        evidence_id: str,
        department: Optional[str] = None,
        location: Optional[str] = None,
        remarks: Optional[str] = None,
        actor_name: str = "Investigator",
        actor_id: Optional[str] = None,
        new_holder_name: Optional[str] = None  # Rejection guard
    ) -> Dict[str, Any]:
        """
        Audited update of non-holder current custody details (location, department, remarks).
        Enforces that holder cannot be changed arbitrarily via edit;
        holder changes MUST follow the transfer workflow.
        """
        clean_ev_id = str(evidence_id).strip()
        info = CustodyService.get_or_create_current_custody(db, clean_ev_id)

        if new_holder_name and info.current_holder_name and new_holder_name.strip().lower() != info.current_holder_name.strip().lower():
            raise ValueError(
                "Holder changes cannot be performed via direct edit. "
                "You must initiate and confirm a custody transfer to change the evidence holder."
            )

        changes = []
        if department is not None and department != info.department:
            changes.append(f"Department: '{info.department}' -> '{department}'")
            info.department = department
        if location is not None and location != info.location:
            changes.append(f"Location: '{info.location}' -> '{location}'")
            info.location = location
        if remarks is not None and remarks != info.remarks:
            changes.append(f"Remarks: '{info.remarks}' -> '{remarks}'")
            info.remarks = remarks

        now_utc = datetime.now(timezone.utc)
        info.updated_at = now_utc

        if changes:
            audit_msg = f"Current custody information updated by {actor_name}: " + "; ".join(changes)
            event_ref = str(uuid4())

            c_log = CustodyLog(
                evidence_id=clean_ev_id,
                case_id=info.case_id,
                investigator_id=actor_id,
                investigator_name=actor_name,
                action="CUSTODY_INFO_UPDATED",
                event_type="UPDATE",
                title="Custody Details Updated",
                result="SUCCESS",
                remarks=audit_msg,
                event_reference=event_ref,
                is_system_action=False,
                actor_is_unverified=True,
                timestamp=now_utc
            )
            db.add(c_log)

            a_log = ActivityLog(
                case_id=info.case_id,
                evidence_id=int(clean_ev_id) if clean_ev_id.isdigit() else None,
                external_evidence_id=clean_ev_id,
                actor_id=actor_id,
                investigator_name=actor_name,
                action="CUSTODY_INFO_UPDATED",
                activity=f"Updated custody details for evidence #{clean_ev_id}",
                outcome="SUCCESS",
                details=audit_msg,
                event_reference=event_ref,
                is_system_action=False,
                actor_is_unverified=True,
                timestamp=now_utc
            )
            db.add(a_log)

        db.commit()
        db.refresh(info)
        return CustodyService.get_current_custody(db, clean_ev_id)

    @staticmethod
    def record_access_event(
        db: Session,
        evidence_id: str,
        actor_name: Optional[str] = None,
        actor_id: Optional[str] = None,
        actor_role: Optional[str] = None,
        purpose: str = "Forensic analysis inspection",
        investigator_name: Optional[str] = None,
        investigator_id: Optional[str] = None,
        action: Optional[str] = None
    ) -> Dict[str, Any]:
        """
        Record that evidence was accessed/viewed for forensic analysis.
        Updates last_accessed timestamp and custody status to 'In Analysis'.
        Viewing/accessing evidence must NOT automatically assign or alter its holder.
        """
        clean_ev_id = str(evidence_id).strip()
        info = CustodyService.get_or_create_current_custody(db, clean_ev_id)
        now_utc = datetime.now(timezone.utc)

        info.last_accessed = now_utc
        info.custody_status = "In Analysis"

        final_actor_name = actor_name or investigator_name or "Investigator"
        final_actor_id = actor_id or investigator_id
        final_action = action or "ACCESSED_FOR_ANALYSIS"

        event_ref = str(uuid4())
        remarks = f"Evidence accessed for analysis by {final_actor_name} ({actor_role or 'Investigator'}). Purpose: {purpose}"

        c_log = CustodyLog(
            evidence_id=clean_ev_id,
            case_id=info.case_id,
            investigator_id=final_actor_id,
            investigator_name=final_actor_name,
            actor_role=actor_role,
            action=final_action,
            event_type="ACCESS",
            title="Accessed for Analysis",
            result="SUCCESS",
            remarks=remarks,
            event_reference=event_ref,
            is_system_action=False,
            actor_is_unverified=True,
            timestamp=now_utc
        )
        db.add(c_log)

        a_log = ActivityLog(
            case_id=info.case_id,
            evidence_id=int(clean_ev_id) if clean_ev_id.isdigit() else None,
            external_evidence_id=clean_ev_id,
            actor_id=final_actor_id,
            investigator_name=final_actor_name,
            action="ACCESSED_FOR_ANALYSIS",
            activity=f"Accessed evidence #{clean_ev_id} for analysis",
            outcome="SUCCESS",
            details=remarks,
            event_reference=event_ref,
            is_system_action=False,
            actor_is_unverified=True,
            timestamp=now_utc
        )
        db.add(a_log)
        db.commit()

        return {"status": "success", "evidence_id": clean_ev_id, "last_accessed": now_utc.isoformat()}

    @staticmethod
    def initiate_transfer(
        db: Session,
        evidence_id: str,
        sender_name: str,
        recipient_name: str,
        remarks: Optional[str] = None,
        sender_id: Optional[str] = None,
        recipient_id: Optional[str] = None,
        sender_role: Optional[str] = None,
        recipient_role: Optional[str] = None,
        case_id: Optional[str] = None
    ) -> Dict[str, Any]:
        """
        Record transfer initiation. Generates a unique transfer reference token.
        Enforces that no pending transfer already exists for this evidence item.
        Result is marked PENDING_RECEIPT; current holder does NOT change until receipt!
        """
        clean_ev_id = str(evidence_id).strip()
        effective_case_id = case_id
        if not effective_case_id:
            adapter = get_backend_adapter()
            ev_item = adapter.get_evidence(clean_ev_id)
            if ev_item and ev_item.case_id:
                effective_case_id = ev_item.case_id

        info = CustodyService.get_or_create_current_custody(db, clean_ev_id, effective_case_id)
        effective_case_id = effective_case_id or info.case_id

        # Validate evidence/case association before custody mutation
        if case_id:
            adapter = get_backend_adapter()
            ev_item = adapter.get_evidence(clean_ev_id)
            if ev_item and ev_item.case_id and ev_item.case_id != case_id:
                raise ValueError(f"Evidence '{clean_ev_id}' does not belong to case '{case_id}'. (Belongs to '{ev_item.case_id}')")

            ev_rec = db.query(EvidenceRecord).filter(
                (EvidenceRecord.external_evidence_id == clean_ev_id) |
                (EvidenceRecord.id == clean_ev_id if clean_ev_id.isdigit() else False)
            ).first()
            if ev_rec and ev_rec.case_id and ev_rec.case_id != case_id:
                raise ValueError(f"Evidence '{clean_ev_id}' does not belong to case '{case_id}'. (Belongs to '{ev_rec.case_id}')")

            if info.case_id and info.case_id != case_id:
                raise ValueError(f"Evidence '{clean_ev_id}' does not belong to case '{case_id}'.")

        # Check for existing pending transfer
        existing_pending = db.query(TransferRecord).filter(
            TransferRecord.evidence_id == clean_ev_id,
            TransferRecord.status == "PENDING_RECEIPT"
        ).first()

        if existing_pending:
            raise ValueError(
                f"Evidence #{clean_ev_id} already has a pending transfer "
                f"({existing_pending.transfer_reference}) to '{existing_pending.recipient_name}'. "
                "Cannot initiate a contradictory transfer until pending transfer is completed or cancelled."
            )

        transfer_ref = f"TRF-{uuid4().hex[:12].upper()}"
        event_ref = str(uuid4())
        now_utc = datetime.now(timezone.utc)

        # Update custody info pending recipient
        info.pending_recipient_id = recipient_id
        info.pending_recipient_name = recipient_name.strip()
        info.custody_status = "PENDING_RECEIPT"
        info.updated_at = now_utc

        transfer_record = TransferRecord(
            transfer_reference=transfer_ref,
            evidence_id=clean_ev_id,
            case_id=effective_case_id,
            sender_id=sender_id,
            sender_name=sender_name.strip(),
            recipient_id=recipient_id,
            recipient_name=recipient_name.strip(),
            status="PENDING_RECEIPT",
            initiated_at=now_utc,
            remarks=remarks
        )
        db.add(transfer_record)

        dispatch_remarks = (
            f"Transfer initiated by {sender_name} ({sender_role or 'Sender'}) to intended recipient "
            f"{recipient_name} ({recipient_role or 'Recipient'}) [PENDING RECEIPT]. Ref: {transfer_ref}. Notes: {remarks or 'None'}"
        )

        custody_entry = CustodyLog(
            evidence_id=clean_ev_id,
            case_id=effective_case_id,
            investigator_id=sender_id,
            investigator_name=sender_name,
            actor_role=sender_role or "Investigator",
            action="TRANSFER_INITIATED",
            event_type="TRANSFER",
            title=f"Transferred to {recipient_name}",
            result="PENDING_RECEIPT",
            remarks=dispatch_remarks,
            transfer_reference=transfer_ref,
            transfer_sender=sender_name,
            transfer_recipient=recipient_name,
            event_reference=event_ref,
            is_system_action=False,
            actor_is_unverified=True,
            timestamp=now_utc
        )
        db.add(custody_entry)

        act_entry = ActivityLog(
            case_id=effective_case_id,
            evidence_id=int(clean_ev_id) if clean_ev_id.isdigit() else None,
            external_evidence_id=clean_ev_id,
            actor_id=sender_id,
            investigator_name=sender_name,
            action="TRANSFER_INITIATED",
            activity=f"Initiated transfer of evidence #{clean_ev_id} to {recipient_name} ({transfer_ref})",
            outcome="PENDING_RECEIPT",
            details=dispatch_remarks,
            event_reference=event_ref,
            is_system_action=False,
            actor_is_unverified=True,
            timestamp=now_utc
        )
        db.add(act_entry)

        db.commit()
        db.refresh(transfer_record)

        return {
            "transfer_reference": transfer_ref,
            "evidence_id": clean_ev_id,
            "case_id": effective_case_id,
            "sender_name": sender_name,
            "recipient_name": recipient_name,
            "status": "PENDING_RECEIPT",
            "initiated_at": now_utc.isoformat(),
            "event_reference": event_ref,
            "message": "Transfer initiated successfully. Evidence remains in PENDING_RECEIPT status until recipient confirms receipt."
        }

    @staticmethod
    def receive_transfer(
        db: Session,
        transfer_reference: str,
        recipient_name: str,
        recipient_id: Optional[str] = None,
        recipient_role: Optional[str] = "Cyber Expert",
        department: Optional[str] = None,
        location: Optional[str] = None,
        remarks: Optional[str] = None
    ) -> Dict[str, Any]:
        """
        Record transfer receipt. Validates recipient and prevents duplicate receipt.
        Updates current holder, assigned timestamp, and marks status as TRANSFERRED / IN_ANALYSIS.
        NO local physical hash recalculation is executed!
        """
        clean_ref = transfer_reference.strip()
        transfer = db.query(TransferRecord).filter(
            TransferRecord.transfer_reference == clean_ref
        ).first()

        if not transfer:
            raise ValueError(f"Transfer reference '{clean_ref}' not found.")

        if transfer.status == "COMPLETED":
            raise ValueError(
                f"Transfer '{clean_ref}' has already been completed on {transfer.received_at.isoformat()}."
            )

        if transfer.status != "PENDING_RECEIPT":
            raise ValueError(
                f"Transfer '{clean_ref}' cannot be received because status is '{transfer.status}'."
            )

        # Validate recipient matches intended recipient
        clean_recipient = recipient_name.strip()
        if clean_recipient.lower() != transfer.recipient_name.lower():
            raise ValueError(
                f"Recipient mismatch: Transfer was dispatched to '{transfer.recipient_name}', "
                f"but receipt attempted by '{clean_recipient}'."
            )

        # Validate recipient ID if transfer has an intended recipient_id
        if transfer.recipient_id:
            if not recipient_id or recipient_id.strip() != transfer.recipient_id.strip():
                raise ValueError(
                    f"Recipient ID mismatch: Transfer was dispatched to recipient ID '{transfer.recipient_id}', "
                    f"but receipt attempted by '{recipient_id or 'None'}'."
                )

        now_utc = datetime.now(timezone.utc)
        transfer.status = "COMPLETED"
        transfer.received_at = now_utc
        transfer.receipt_remarks = remarks

        event_ref = str(uuid4())

        # Update CurrentCustodyInfo: holder officially changes upon confirmed receipt
        info = CustodyService.get_or_create_current_custody(db, str(transfer.evidence_id), transfer.case_id)
        info.current_holder_id = recipient_id or transfer.recipient_id
        info.current_holder_name = clean_recipient
        info.current_holder_role = recipient_role
        if department:
            info.department = department
        if location:
            info.location = location
        info.assigned_on = now_utc
        info.pending_recipient_id = None
        info.pending_recipient_name = None
        info.custody_status = "In Analysis"
        info.updated_at = now_utc

        receipt_remarks = (
            f"Physical custody received and accepted by {clean_recipient} ({recipient_role or 'Recipient'}). "
            f"Ref: {clean_ref}. Notes: {remarks or 'Custody confirmed'}"
        )

        custody_entry = CustodyLog(
            evidence_id=str(transfer.evidence_id),
            case_id=transfer.case_id,
            investigator_id=recipient_id,
            investigator_name=clean_recipient,
            actor_role=recipient_role,
            action="TRANSFER_RECEIVED",
            event_type="TRANSFER",
            title="Custody Received",
            result="SUCCESS",
            remarks=receipt_remarks,
            transfer_reference=clean_ref,
            transfer_sender=transfer.sender_name,
            transfer_recipient=clean_recipient,
            event_reference=event_ref,
            is_system_action=False,
            actor_is_unverified=True,
            timestamp=now_utc
        )
        db.add(custody_entry)

        act_entry = ActivityLog(
            case_id=transfer.case_id,
            evidence_id=int(transfer.evidence_id) if str(transfer.evidence_id).isdigit() else None,
            external_evidence_id=str(transfer.evidence_id),
            actor_id=recipient_id,
            investigator_name=clean_recipient,
            action="TRANSFER_RECEIVED",
            activity=f"Acknowledged receipt of evidence #{transfer.evidence_id} from {transfer.sender_name} ({clean_ref})",
            outcome="SUCCESS",
            details=receipt_remarks,
            event_reference=event_ref,
            is_system_action=False,
            actor_is_unverified=True,
            timestamp=now_utc
        )
        db.add(act_entry)

        db.commit()

        return {
            "transfer_reference": clean_ref,
            "evidence_id": str(transfer.evidence_id),
            "case_id": transfer.case_id,
            "sender_name": transfer.sender_name,
            "recipient_name": clean_recipient,
            "status": "COMPLETED",
            "received_at": now_utc.isoformat(),
            "event_reference": event_ref,
            "current_custody": CustodyService.get_current_custody(db, str(transfer.evidence_id)),
            "message": "Transfer receipt confirmed and custody transferred successfully."
        }

    @staticmethod
    def get_transfer_history(
        db: Session,
        evidence_id: str,
        page: int = 1,
        page_size: int = 10
    ) -> Dict[str, Any]:
        """
        Transfer history table matching Screenshot 2 right panel with pagination.
        """
        clean_ev_id = str(evidence_id).strip()
        query = db.query(TransferRecord).filter(
            TransferRecord.evidence_id == clean_ev_id
        ).order_by(TransferRecord.initiated_at.asc())

        total = query.count()
        offset = (max(1, page) - 1) * page_size
        records = query.offset(offset).limit(page_size).all()

        rows = []
        for idx, tr in enumerate(records, start=offset + 1):
            date_time_formatted = tr.initiated_at.strftime("%d %b %Y %I:%M %p") if tr.initiated_at else "N/A"
            rows.append({
                "row_number": idx,
                "transfer_reference": tr.transfer_reference,
                "from_identity": tr.sender_name,
                "to_identity": tr.recipient_name,
                "initiated_at": tr.initiated_at.isoformat() if tr.initiated_at else None,
                "received_at": tr.received_at.isoformat() if tr.received_at else None,
                "date_time_display": date_time_formatted,
                "status": tr.status,
                "remarks": tr.remarks or tr.receipt_remarks or "Custody transfer"
            })

        return {
            "evidence_id": clean_ev_id,
            "total": total,
            "page": page,
            "page_size": page_size,
            "transfers": rows
        }

    @staticmethod
    def sync_external_events(db: Session, evidence_id: Optional[str] = None, case_id: Optional[str] = None):
        """
        Idempotently ingest external custody events from the BackendAdapter.
        Repeated calls guarantee zero duplicate entries via external_event_id.
        """
        adapter = get_backend_adapter()
        target_case_id = case_id
        if not target_case_id and evidence_id:
            clean_ev = str(evidence_id).strip()
            ev_item = adapter.get_evidence(clean_ev)
            if ev_item and ev_item.case_id:
                target_case_id = ev_item.case_id

        if not target_case_id and evidence_id:
            clean_ev = str(evidence_id).strip()
            info = db.query(CurrentCustodyInfo).filter(CurrentCustodyInfo.evidence_id == clean_ev).first()
            if info and info.case_id and info.case_id != "CASE-DEFAULT":
                target_case_id = info.case_id

        if not target_case_id and evidence_id:
            clean_ev = str(evidence_id).strip()
            ev_rec = db.query(EvidenceRecord).filter(
                (EvidenceRecord.external_evidence_id == clean_ev) |
                (EvidenceRecord.id == clean_ev if clean_ev.isdigit() else False)
            ).first()
            if ev_rec and ev_rec.case_id:
                target_case_id = ev_rec.case_id

        events = adapter.get_external_events(case_id=target_case_id, evidence_id=evidence_id)
        for ev in events:
            # Check for existing
            exists = db.query(CustodyLog).filter(CustodyLog.external_event_id == ev.external_event_id).first()
            if not exists:
                c_log = CustodyLog(
                    evidence_id=str(ev.evidence_id),
                    case_id=ev.case_id,
                    external_event_id=ev.external_event_id,
                    event_type=ev.event_type,
                    title=ev.title,
                    investigator_id=ev.actor_id,
                    investigator_name=ev.actor_name,
                    actor_role=ev.actor_role,
                    action=ev.event_type,
                    result=ev.outcome,
                    remarks=ev.description,
                    source_reference=ev.source_reference,
                    is_system_action=ev.is_system_action,
                    actor_is_unverified=False,
                    timestamp=ev.timestamp
                )
                db.add(c_log)

                # Only update holder if event is an explicit assignment or confirmed custody transfer
                if not ev.is_system_action and ev.actor_name and ev.event_type in ("ASSIGNMENT", "TRANSFER_RECEIVED", "CUSTODY_TRANSFER"):
                    info = CustodyService.get_or_create_current_custody(db, str(ev.evidence_id), ev.case_id)
                    if not info.current_holder_name:
                        info.current_holder_name = ev.actor_name
                        info.current_holder_id = ev.actor_id
                        info.current_holder_role = ev.actor_role
                        info.assigned_on = ev.timestamp
                        # Do not invent "In Analysis" - use actual status if known or leave None
                        if not info.custody_status and ev.outcome:
                            info.custody_status = ev.outcome

        db.commit()

    @staticmethod
    def _log_activity(
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
        from app.services.activity_service import ActivityService
        return ActivityService.log_activity(
            db=db,
            investigator_name=investigator_name,
            activity=activity,
            case_id=case_id,
            evidence_id=evidence_id,
            external_evidence_id=external_evidence_id,
            actor_id=actor_id,
            action=action,
            outcome=outcome,
            details=details,
            ip_address=ip_address,
            timestamp=timestamp
        )