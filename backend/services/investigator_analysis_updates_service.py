import os
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional, List, Dict, Any, Tuple
from fastapi import HTTPException, status
from sqlalchemy.orm import Session
from sqlalchemy import or_, func, desc

from models.case import Case
from models.user import User
from models.evidence import Evidence
from models.evidence_hash import EvidenceHash
from models.evidence_record import EvidenceRecord
from models.epra_result import EPRAResult
from models.cbir_result import CBIRResult
from models.possible_entity import PossibleEntity, PossibleEntityEvidenceLink
from models.evidence_link import EvidenceLink
from models.report_record import ReportRecord
from models.case_timeline import CaseTimeline

from schemas.investigator_analysis_updates import (
    AnalysisUpdatesSummaryResponse,
    AssignedCyberExpertInfo,
    ModuleStatusItem,
    AnalysisModulesStatus,
    CaseIntelligenceSummary,
    CaseLatestUpdate,
    CaseAnalysisOverviewItem,
    CaseAnalysisOverviewPage,
    AnalysisPulseItem,
    AnalysisPulsePage,
)

SUPPORTED_IMAGE_EXTENSIONS = (".jpg", ".jpeg", ".png", ".bmp", ".webp")


def is_image_evidence(evidence: Evidence) -> bool:
    """Check whether an evidence record represents an image file."""
    if not evidence:
        return False
    if evidence.file_type and "image" in evidence.file_type.lower():
        return True
    name = (evidence.file_name or "").lower()
    path = (evidence.file_path or "").lower()
    return any(name.endswith(ext) or path.endswith(ext) for ext in SUPPORTED_IMAGE_EXTENSIONS)


class InvestigatorAnalysisUpdatesService:

    @staticmethod
    def _evaluate_case_analysis(db: Session, case: Case) -> CaseAnalysisOverviewItem:
        """
        Dynamically derives complete, truthful case-level forensic analysis state
        across all 7 modules without hardcoded placeholders or mock percentages.
        """
        # 1. Resolve Assigned Cyber Expert
        assigned_expert: Optional[AssignedCyberExpertInfo] = None
        if case.cyber_expert_id:
            expert = db.query(User).filter(User.id == case.cyber_expert_id).first()
            if expert:
                assigned_expert = AssignedCyberExpertInfo(
                    id=expert.id,
                    name=expert.full_name,
                    email=expert.email
                )

        # 2. Fetch Evidence items for this case
        evidences = (
            db.query(Evidence)
            .filter(Evidence.case_id == case.id)
            .order_by(Evidence.id.asc())
            .all()
        )
        total_evidence = len(evidences)
        ev_ids = [e.id for e in evidences]
        has_images = any(is_image_evidence(e) for e in evidences)

        # Candidate updates tracker for determining latest_update
        candidate_updates: List[Tuple[datetime, str, str]] = []

        # ======================================================================
        # MODULE 1: INTEGRITY (SHA-256 Verification)
        # ======================================================================
        hashes: List[EvidenceHash] = []
        if ev_ids:
            hashes = db.query(EvidenceHash).filter(EvidenceHash.evidence_id.in_(ev_ids)).all()

        integrity_updated_at: Optional[datetime] = None
        if hashes:
            integrity_updated_at = max(
                [h.verified_at or h.created_at for h in hashes if (h.verified_at or h.created_at)],
                default=None
            )

        tampered_hashes = [
            h for h in hashes
            if h.tampered is True
            or h.hash_match is False
            or str(h.integrity_status).upper() in ["TAMPERED", "MISMATCH"]
        ]
        verified_hashes = [
            h for h in hashes
            if str(h.integrity_status).capitalize() == "Verified"
        ]

        is_integrity_completed = (len(hashes) >= total_evidence and total_evidence > 0)

        if total_evidence == 0:
            integrity_status = "PENDING"
            integrity_details = "No evidence uploaded"
            intelligence_integrity = "PENDING"
        elif tampered_hashes:
            integrity_status = "ATTENTION_REQUIRED"
            integrity_details = f"Tampered hash detected ({len(tampered_hashes)} item{'s' if len(tampered_hashes) > 1 else ''})"
            intelligence_integrity = "ATTENTION_REQUIRED"
        elif len(verified_hashes) == total_evidence and total_evidence > 0:
            integrity_status = "COMPLETED"
            integrity_details = f"All {total_evidence} evidence files verified"
            intelligence_integrity = "VERIFIED"
        elif len(verified_hashes) > 0:
            integrity_status = "IN_PROGRESS"
            integrity_details = f"{len(verified_hashes)}/{total_evidence} files verified"
            intelligence_integrity = "PENDING"
        else:
            integrity_status = "PENDING"
            integrity_details = f"0/{total_evidence} files verified"
            intelligence_integrity = "PENDING"

        integrity_mod = ModuleStatusItem(
            status=integrity_status,
            is_completed=is_integrity_completed,
            updated_at=integrity_updated_at,
            details=integrity_details
        )
        if integrity_updated_at and integrity_status != "PENDING":
            candidate_updates.append((
                integrity_updated_at,
                "INTEGRITY",
                f"Evidence hash integrity check: {integrity_details}"
            ))

        # ======================================================================
        # MODULE 2: METADATA EXTRACTION
        # ======================================================================
        meta_records = db.query(EvidenceRecord).filter(
            EvidenceRecord.case_id.in_([str(case.id), str(case.case_id)])
        ).all()
        meta_count = len(meta_records)

        meta_updated_at: Optional[datetime] = None
        if meta_records:
            meta_updated_at = max(
                [
                    r.retrieved_at or r.cached_at or r.created_at or r.uploaded_at
                    for r in meta_records
                    if (r.retrieved_at or r.cached_at or r.created_at or r.uploaded_at)
                ],
                default=None
            )

        is_metadata_completed = (meta_count >= total_evidence and total_evidence > 0)

        if total_evidence == 0:
            metadata_status = "PENDING"
            metadata_details = "No evidence uploaded"
        elif is_metadata_completed:
            metadata_status = "COMPLETED"
            metadata_details = f"{meta_count} files synchronized"
        elif meta_count > 0:
            metadata_status = "IN_PROGRESS"
            metadata_details = f"{meta_count}/{total_evidence} files synchronized"
        else:
            metadata_status = "PENDING"
            metadata_details = f"0/{total_evidence} files synchronized"

        metadata_mod = ModuleStatusItem(
            status=metadata_status,
            is_completed=is_metadata_completed,
            updated_at=meta_updated_at,
            details=metadata_details
        )
        if meta_updated_at and metadata_status != "PENDING":
            candidate_updates.append((
                meta_updated_at,
                "METADATA",
                f"Evidence metadata extraction: {metadata_details}"
            ))

        # ======================================================================
        # MODULE 3: EPRA (Evidence Prioritization & Risk Analysis)
        # ======================================================================
        epra_records = (
            db.query(EPRAResult)
            .filter(EPRAResult.case_id == case.id)
            .all()
        )
        epra_count = len(epra_records)

        epra_updated_at: Optional[datetime] = None
        if epra_records:
            epra_updated_at = max(
                [r.processed_at or r.created_at for r in epra_records if (r.processed_at or r.created_at)],
                default=None
            )

        # Derive highest EPRA priority
        priority_rank = {"Critical": 1, "High": 2, "Medium": 3, "Low": 4, "Very Low": 5}
        highest_epra_priority: Optional[str] = None
        best_rank = 99

        for ep in epra_records:
            if ep.priority:
                p_text = ep.priority.strip()
                p_key = p_text.title()
                rnk = priority_rank.get(p_key, 90)
                if rnk < best_rank:
                    best_rank = rnk
                    highest_epra_priority = p_key

        completed_epra_count = sum(1 for r in epra_records if r.analysis_status == "COMPLETE")
        is_epra_completed = (epra_count >= total_evidence and completed_epra_count == total_evidence and total_evidence > 0)

        if total_evidence == 0:
            epra_status = "PENDING"
            epra_details = "No evidence uploaded"
        elif is_epra_completed:
            epra_status = "COMPLETED"
            epra_details = f"All {total_evidence} items prioritized (Highest: {highest_epra_priority or 'None'})"
        elif epra_count > 0:
            epra_status = "IN_PROGRESS"
            epra_details = f"{completed_epra_count}/{total_evidence} items prioritized"
        else:
            epra_status = "PENDING"
            epra_details = f"0/{total_evidence} items prioritized"

        epra_mod = ModuleStatusItem(
            status=epra_status,
            is_completed=is_epra_completed,
            updated_at=epra_updated_at,
            details=epra_details
        )
        if epra_updated_at and epra_status != "PENDING":
            candidate_updates.append((
                epra_updated_at,
                "EPRA",
                f"EPRA prioritization completed ({epra_details})"
            ))

        # ======================================================================
        # MODULE 4: CBIR (Content-Based Image Retrieval)
        # ======================================================================
        cbir_updated_at: Optional[datetime] = None

        if not has_images:
            cbir_status = "N/A"
            is_cbir_completed = False
            cbir_details = "No image evidence applicable"
        else:
            cbir_records = db.query(CBIRResult).filter(CBIRResult.case_id == case.id).all()
            if cbir_records:
                cbir_updated_at = max([c.created_at for c in cbir_records if c.created_at], default=None)
                cbir_status = "COMPLETED"
                is_cbir_completed = True
                cbir_details = f"{len(cbir_records)} visual comparisons recorded"
            else:
                image_count = sum(1 for e in evidences if is_image_evidence(e))
                cbir_status = "PENDING"
                is_cbir_completed = False
                cbir_details = f"{image_count} image(s) awaiting CBIR comparison"

        cbir_mod = ModuleStatusItem(
            status=cbir_status,
            is_completed=is_cbir_completed,
            updated_at=cbir_updated_at,
            details=cbir_details
        )
        if cbir_updated_at and cbir_status == "COMPLETED":
            candidate_updates.append((
                cbir_updated_at,
                "CBIR",
                f"CBIR visual similarity comparison updated ({cbir_details})"
            ))

        # ======================================================================
        # MODULE 5: POSSIBLE ENTITY / SUSPECT RANKING
        # ======================================================================
        entities = db.query(PossibleEntity).filter(PossibleEntity.case_id == case.id).all()
        entity_count = len(entities)

        entity_updated_at: Optional[datetime] = None
        if entities:
            entity_updated_at = max(
                [e.processed_at or e.created_at for e in entities if (e.processed_at or e.created_at)],
                default=None
            )

        entity_event = db.query(CaseTimeline).filter(
            CaseTimeline.case_id == case.id,
            or_(
                CaseTimeline.event.ilike("%suspect%"),
                CaseTimeline.event.ilike("%entity%")
            )
        ).first()

        if entity_count > 0:
            entity_status = "COMPLETED"
            is_entity_completed = True
            entity_details = f"{entity_count} possible entities ranked"
        elif entity_event:
            entity_status = "COMPLETED"
            is_entity_completed = True
            entity_details = "0 suspect entities discovered"
            if not entity_updated_at:
                entity_updated_at = entity_event.created_at
        elif total_evidence == 0:
            entity_status = "PENDING"
            is_entity_completed = False
            entity_details = "No evidence uploaded"
        else:
            entity_status = "PENDING"
            is_entity_completed = False
            entity_details = "Entity ranking pending"

        entity_mod = ModuleStatusItem(
            status=entity_status,
            is_completed=is_entity_completed,
            updated_at=entity_updated_at,
            details=entity_details
        )
        if entity_updated_at and entity_status == "COMPLETED":
            candidate_updates.append((
                entity_updated_at,
                "ENTITY_RANKING",
                f"Suspect entity ranking updated: {entity_details}"
            ))

        # ======================================================================
        # MODULE 6: RELATIONSHIP ANALYSIS
        # ======================================================================
        custom_links = db.query(EvidenceLink).filter(EvidenceLink.case_id == case.id).all()

        entity_links = []
        if entities and ev_ids:
            entity_links = db.query(PossibleEntityEvidenceLink).filter(
                PossibleEntityEvidenceLink.entity_id.in_([pe.id for pe in entities]),
                PossibleEntityEvidenceLink.evidence_id.in_(ev_ids)
            ).all()

        cbir_matches = []
        if has_images:
            cbir_matches = db.query(CBIRResult).filter(
                CBIRResult.case_id == case.id,
                CBIRResult.sha256_exact_duplicate == False
            ).all()

        # Duplicate pairs from EvidenceHash
        dup_count = 0
        if len(hashes) > 1:
            sha_counts: Dict[str, int] = {}
            for h in hashes:
                if h.sha256_hash:
                    sha_counts[h.sha256_hash] = sha_counts.get(h.sha256_hash, 0) + 1
            dup_count = sum(cnt - 1 for cnt in sha_counts.values() if cnt > 1)

        total_relationships = len(custom_links) + len(entity_links) + len(cbir_matches) + dup_count

        rel_timestamps = (
            [l.created_at for l in custom_links if l.created_at] +
            [el.created_at for el in entity_links if el.created_at] +
            [cm.created_at for cm in cbir_matches if cm.created_at]
        )
        relationship_updated_at = max(rel_timestamps, default=None)

        rel_event = db.query(CaseTimeline).filter(
            CaseTimeline.case_id == case.id,
            or_(
                CaseTimeline.event.ilike("%relationship%"),
                CaseTimeline.event.ilike("%graph%")
            )
        ).first()

        if total_relationships > 0:
            rel_status = "COMPLETED"
            is_rel_completed = True
            rel_details = f"{total_relationships} relational connections found"
        elif rel_event:
            rel_status = "COMPLETED"
            is_rel_completed = True
            rel_details = "0 relationships discovered"
            if not relationship_updated_at:
                relationship_updated_at = rel_event.created_at
        elif total_evidence == 0:
            rel_status = "PENDING"
            is_rel_completed = False
            rel_details = "No evidence uploaded"
        else:
            rel_status = "PENDING"
            is_rel_completed = False
            rel_details = "Relationship analysis pending"

        relationship_mod = ModuleStatusItem(
            status=rel_status,
            is_completed=is_rel_completed,
            updated_at=relationship_updated_at,
            details=rel_details
        )
        if relationship_updated_at and rel_status == "COMPLETED":
            candidate_updates.append((
                relationship_updated_at,
                "RELATIONSHIP",
                f"Relationship analysis updated: {rel_details}"
            ))

        # ======================================================================
        # MODULE 7: TECHNICAL REPORT
        # ======================================================================
        reports = (
            db.query(ReportRecord)
            .filter(
                ReportRecord.case_id.in_([str(case.id), str(case.case_id)]),
                ReportRecord.is_draft == False
            )
            .order_by(ReportRecord.generated_at.desc())
            .all()
        )

        report_updated_at: Optional[datetime] = None
        if reports:
            report_updated_at = reports[0].generated_at
            report_status = "COMPLETED"
            is_report_completed = True
            report_details = f"{len(reports)} report(s) generated ({reports[0].report_type})"
            intelligence_report_status = "COMPLETED"
        else:
            report_status = "PENDING"
            is_report_completed = False
            report_details = "No report generated yet"
            intelligence_report_status = "PENDING"

        technical_report_mod = ModuleStatusItem(
            status=report_status,
            is_completed=is_report_completed,
            updated_at=report_updated_at,
            details=report_details
        )
        if report_updated_at and report_status == "COMPLETED":
            candidate_updates.append((
                report_updated_at,
                "TECHNICAL_REPORT",
                f"Technical report generated: {reports[0].file_name}"
            ))

        # ======================================================================
        # 8. CASE ANALYSIS PROGRESS (0 - 100%)
        # ======================================================================
        all_modules = [
            integrity_mod,
            metadata_mod,
            epra_mod,
            cbir_mod,
            entity_mod,
            relationship_mod,
            technical_report_mod
        ]
        # Exclude N/A modules from denominator
        applicable_modules = [m for m in all_modules if m.status != "N/A"]

        if total_evidence == 0:
            analysis_progress = 0.0
        else:
            completed_count = sum(1 for m in applicable_modules if m.is_completed)
            analysis_progress = round((completed_count / len(applicable_modules)) * 100, 1) if applicable_modules else 0.0

        # ======================================================================
        # 9. ATTENTION REQUIRED EVALUATION
        # ======================================================================
        attention_reasons: List[str] = []

        # Condition 1: Compromised evidence integrity
        if tampered_hashes:
            for th in tampered_hashes:
                attention_reasons.append(f"Evidence integrity compromised ({th.file_name})")

        # Condition 2: Critical priority EPRA evidence
        critical_epra_count = sum(1 for ep in epra_records if str(ep.priority).title() == "Critical")
        if critical_epra_count > 0:
            attention_reasons.append(
                f"Critical EPRA evidence identified ({critical_epra_count} item{'s' if critical_epra_count > 1 else ''})"
            )

        # Condition 3: High or Critical Priority Case pending action
        if case.priority in ["Critical", "High"] and case.status == "Open" and analysis_progress == 0.0:
            attention_reasons.append(f"{case.priority} priority case pending forensic analysis")

        attention_required = len(attention_reasons) > 0


        # ======================================================================
        # 10. CASE ANALYSIS STATE
        # ======================================================================
        if attention_required:
            analysis_state = "ATTENTION_REQUIRED"
        elif analysis_progress >= 100.0:
            analysis_state = "COMPLETED"
        elif analysis_progress > 0.0:
            analysis_state = "IN_ANALYSIS"
        else:
            analysis_state = "PENDING"

        # ======================================================================
        # 11. LATEST UPDATE RESOLUTION
        # ======================================================================
        latest_update: Optional[CaseLatestUpdate] = None
        if candidate_updates:
            # Sort by datetime descending
            candidate_updates.sort(
                key=lambda x: (x[0].timestamp() if x[0].tzinfo is None else x[0].replace(tzinfo=timezone.utc).timestamp()),
                reverse=True
            )
            best_ts, best_mod, best_msg = candidate_updates[0]
            latest_update = CaseLatestUpdate(
                module=best_mod,
                message=best_msg,
                updated_at=best_ts
            )

        # Assemble composite structures
        analysis_modules = AnalysisModulesStatus(
            integrity=integrity_mod,
            metadata=metadata_mod,
            epra=epra_mod,
            cbir=cbir_mod,
            entity_ranking=entity_mod,
            relationship=relationship_mod,
            technical_report=technical_report_mod
        )

        case_intelligence = CaseIntelligenceSummary(
            highest_epra_priority=highest_epra_priority,
            possible_entities=entity_count,
            relationships_found=total_relationships,
            integrity_status=intelligence_integrity,
            technical_report_status=intelligence_report_status,
            total_evidence=total_evidence
        )

        return CaseAnalysisOverviewItem(
            id=case.id,
            case_id=case.case_id,
            title=case.title,
            crime_type=case.description if (case.description and len(case.description) < 60) else "Digital Forensics",
            case_priority=case.priority,
            case_status=case.status,
            assigned_cyber_expert=assigned_expert,
            analysis_progress=analysis_progress,
            analysis_state=analysis_state,
            analysis_modules=analysis_modules,
            case_intelligence=case_intelligence,
            latest_update=latest_update,
            attention_required=attention_required,
            attention_reasons=attention_reasons
        )

    # ==========================================================================
    # API 1: GLOBAL SUMMARY
    # ==========================================================================

    @classmethod
    def get_analysis_updates_summary(
        cls,
        db: Session,
        current_user: User
    ) -> AnalysisUpdatesSummaryResponse:
        """
        Calculates case-level analysis update totals strictly for cases
        assigned to the authenticated Investigator (Case.investigator_id == current_user.id).
        """
        assigned_cases = (
            db.query(Case)
            .filter(Case.investigator_id == current_user.id)
            .all()
        )

        if not assigned_cases:
            return AnalysisUpdatesSummaryResponse(
                total_cases=0,
                in_analysis=0,
                attention_required=0,
                completed=0,
                pending=0,
                last_refreshed=datetime.now(timezone.utc)
            )

        overviews = [cls._evaluate_case_analysis(db, c) for c in assigned_cases]

        total_cases = len(overviews)
        in_analysis = sum(1 for o in overviews if o.analysis_state == "IN_ANALYSIS")
        attention_required = sum(1 for o in overviews if o.analysis_state == "ATTENTION_REQUIRED")
        completed = sum(1 for o in overviews if o.analysis_state == "COMPLETED")
        pending = sum(1 for o in overviews if o.analysis_state == "PENDING")

        return AnalysisUpdatesSummaryResponse(
            total_cases=total_cases,
            in_analysis=in_analysis,
            attention_required=attention_required,
            completed=completed,
            pending=pending,
            last_refreshed=datetime.now(timezone.utc)
        )

    # ==========================================================================
    # API 2: CASE ANALYSIS OVERVIEW
    # ==========================================================================

    @classmethod
    def get_cases_analysis_overview(
        cls,
        db: Session,
        current_user: User,
        search: Optional[str] = None,
        analysis_state: Optional[str] = None,
        attention_required: Optional[bool] = None,
        case_status: Optional[str] = None,
        page: int = 1,
        page_size: int = 10
    ) -> CaseAnalysisOverviewPage:
        """
        Returns paginated, searchable, filterable case analysis overview items
        for all cases assigned to the current investigator.
        """
        query = db.query(Case).filter(Case.investigator_id == current_user.id)

        if isinstance(case_status, str) and case_status.strip() and case_status.strip().upper() != "ALL":
            query = query.filter(Case.status == case_status.strip())

        if isinstance(search, str) and search.strip():
            s = f"%{search.strip().lower()}%"
            query = query.filter(
                or_(
                    func.lower(Case.case_id).like(s),
                    func.lower(Case.title).like(s),
                    func.lower(Case.description).like(s)
                )
            )

        assigned_cases = query.order_by(Case.created_at.desc()).all()

        # Derive case analysis overviews
        overview_items = [cls._evaluate_case_analysis(db, c) for c in assigned_cases]

        # Apply analysis_state filter
        if isinstance(analysis_state, str) and analysis_state.strip().upper() != "ALL":
            target_state = analysis_state.strip().upper()
            overview_items = [o for o in overview_items if o.analysis_state == target_state]

        # Apply attention_required filter
        if attention_required is not None:
            overview_items = [o for o in overview_items if o.attention_required == attention_required]

        total = len(overview_items)
        total_pages = (total + page_size - 1) // page_size if page_size > 0 else 1
        offset = (max(1, page) - 1) * page_size
        page_items = overview_items[offset:offset + page_size]

        return CaseAnalysisOverviewPage(
            total=total,
            page=page,
            page_size=page_size,
            total_pages=total_pages,
            items=page_items
        )

    # ==========================================================================
    # API 3: SINGLE CASE ANALYSIS OVERVIEW
    # ==========================================================================

    @classmethod
    def get_single_case_analysis_overview(
        cls,
        db: Session,
        current_user: User,
        case_identifier: str | int
    ) -> CaseAnalysisOverviewItem:
        """
        Retrieves complete case analysis overview for a single assigned case.
        Enforces strict investigator ownership.
        """
        clean_id = str(case_identifier).strip()
        query = db.query(Case).filter(Case.investigator_id == current_user.id)

        if clean_id.isdigit():
            case = query.filter(
                or_(
                    Case.id == int(clean_id),
                    Case.case_id == clean_id
                )
            ).first()
        else:
            case = query.filter(Case.case_id == clean_id).first()

        if not case:
            # Check if case exists but belongs to another investigator
            cross_case = db.query(Case).filter(
                or_(
                    Case.id == (int(clean_id) if clean_id.isdigit() else -1),
                    Case.case_id == clean_id
                )
            ).first()

            if cross_case:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="Access denied: Case is not assigned to the authenticated Investigator."
                )
            else:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail=f"Case '{case_identifier}' not found."
                )

        return cls._evaluate_case_analysis(db, case)

    # ==========================================================================
    # API 4: ANALYSIS PULSE (RECENT ACTIVITY)
    # ==========================================================================

    @classmethod
    def get_analysis_pulse_activity(
        cls,
        db: Session,
        current_user: User,
        module: Optional[str] = None,
        limit: int = 20,
        page: int = 1
    ) -> AnalysisPulsePage:
        """
        Returns chronological case-level forensic analysis activities across
        all cases assigned to the current investigator.
        Ordered newest first.
        """
        assigned_cases = (
            db.query(Case)
            .filter(Case.investigator_id == current_user.id)
            .all()
        )

        if not assigned_cases:
            return AnalysisPulsePage(
                total=0,
                page=page,
                limit=limit,
                total_pages=1,
                items=[]
            )

        assigned_case_ids = [c.id for c in assigned_cases]
        case_map = {c.id: c for c in assigned_cases}
        case_code_map = {str(c.case_id): c for c in assigned_cases}

        events: List[AnalysisPulseItem] = []

        # 1. Technical Reports
        # Lookup by case integer ID strings and case_id codes
        match_case_strs = [str(cid) for cid in assigned_case_ids] + list(case_code_map.keys())
        reports = (
            db.query(ReportRecord)
            .filter(
                ReportRecord.case_id.in_(match_case_strs),
                ReportRecord.is_draft == False
            )
            .all()
        )
        for r in reports:
            parent_case = case_code_map.get(r.case_id) or case_map.get(int(r.case_id) if r.case_id.isdigit() else -1)
            c_code = parent_case.case_id if parent_case else r.case_id
            c_title = parent_case.title if parent_case else (r.case_title or "Investigation")
            dt = r.generated_at
            if dt:
                events.append(
                    AnalysisPulseItem(
                        case_id=c_code,
                        case_title=c_title,
                        module="TECHNICAL_REPORT",
                        event_type="TECHNICAL_REPORT_GENERATED",
                        message=f"Case {c_code} — Technical Report Generated ({r.report_type})",
                        status="COMPLETED",
                        timestamp=dt,
                        timestamp_formatted=dt.strftime("%d %b %Y, %H:%M")
                    )
                )

        # 2. EPRA Analysis Runs (Grouped by case and processed_at timestamp)
        epra_runs = (
            db.query(
                EPRAResult.case_id,
                EPRAResult.processed_at,
                func.count(EPRAResult.id).label("count")
            )
            .filter(EPRAResult.case_id.in_(assigned_case_ids))
            .group_by(EPRAResult.case_id, EPRAResult.processed_at)
            .all()
        )
        for cid, dt, cnt in epra_runs:
            if dt and cid in case_map:
                c = case_map[cid]
                events.append(
                    AnalysisPulseItem(
                        case_id=c.case_id,
                        case_title=c.title,
                        module="EPRA",
                        event_type="EPRA_ANALYSIS_COMPLETED",
                        message=f"Case {c.case_id} — EPRA Risk Prioritization Completed ({cnt} evidence items)",
                        status="COMPLETED",
                        timestamp=dt,
                        timestamp_formatted=dt.strftime("%d %b %Y, %H:%M")
                    )
                )

        # 3. CBIR Visual Comparisons (Grouped by case and created_at timestamp)
        cbir_runs = (
            db.query(
                CBIRResult.case_id,
                CBIRResult.created_at,
                func.count(CBIRResult.id).label("count")
            )
            .filter(CBIRResult.case_id.in_(assigned_case_ids))
            .group_by(CBIRResult.case_id, CBIRResult.created_at)
            .all()
        )
        for cid, dt, cnt in cbir_runs:
            if dt and cid in case_map:
                c = case_map[cid]
                events.append(
                    AnalysisPulseItem(
                        case_id=c.case_id,
                        case_title=c.title,
                        module="CBIR",
                        event_type="CBIR_COMPARISON_UPDATED",
                        message=f"Case {c.case_id} — CBIR Visual Similarity Comparison Updated ({cnt} pairs evaluated)",
                        status="COMPLETED",
                        timestamp=dt,
                        timestamp_formatted=dt.strftime("%d %b %Y, %H:%M")
                    )
                )

        # 4. Possible Entity / Suspect Rankings (Grouped by case and processed_at timestamp)
        entity_runs = (
            db.query(
                PossibleEntity.case_id,
                PossibleEntity.processed_at,
                func.count(PossibleEntity.id).label("count")
            )
            .filter(PossibleEntity.case_id.in_(assigned_case_ids))
            .group_by(PossibleEntity.case_id, PossibleEntity.processed_at)
            .all()
        )
        for cid, dt, cnt in entity_runs:
            if dt and cid in case_map:
                c = case_map[cid]
                events.append(
                    AnalysisPulseItem(
                        case_id=c.case_id,
                        case_title=c.title,
                        module="ENTITY_RANKING",
                        event_type="ENTITY_RANKING_UPDATED",
                        message=f"Case {c.case_id} — Suspect Entity Ranking Updated ({cnt} possible entities)",
                        status="COMPLETED",
                        timestamp=dt,
                        timestamp_formatted=dt.strftime("%d %b %Y, %H:%M")
                    )
                )

        # 5. Relationship Links (Grouped by case and created_at timestamp)
        rel_runs = (
            db.query(
                EvidenceLink.case_id,
                EvidenceLink.created_at,
                func.count(EvidenceLink.id).label("count")
            )
            .filter(EvidenceLink.case_id.in_(assigned_case_ids))
            .group_by(EvidenceLink.case_id, EvidenceLink.created_at)
            .all()
        )
        for cid, dt, cnt in rel_runs:
            if dt and cid in case_map:
                c = case_map[cid]
                events.append(
                    AnalysisPulseItem(
                        case_id=c.case_id,
                        case_title=c.title,
                        module="RELATIONSHIP",
                        event_type="RELATIONSHIP_ANALYSIS_UPDATED",
                        message=f"Case {c.case_id} — Relationship Analysis Updated ({cnt} links established)",
                        status="COMPLETED",
                        timestamp=dt,
                        timestamp_formatted=dt.strftime("%d %b %Y, %H:%M")
                    )
                )

        # 6. Cryptographic Hash Integrity Verifications
        hash_runs = (
            db.query(
                Evidence.case_id,
                EvidenceHash.verified_at,
                func.count(EvidenceHash.id).label("count")
            )
            .join(Evidence, EvidenceHash.evidence_id == Evidence.id)
            .filter(
                Evidence.case_id.in_(assigned_case_ids),
                EvidenceHash.verified_at.isnot(None)
            )
            .group_by(Evidence.case_id, EvidenceHash.verified_at)
            .all()
        )
        for cid, dt, cnt in hash_runs:
            if dt and cid in case_map:
                c = case_map[cid]
                events.append(
                    AnalysisPulseItem(
                        case_id=c.case_id,
                        case_title=c.title,
                        module="INTEGRITY",
                        event_type="INTEGRITY_VERIFICATION_COMPLETED",
                        message=f"Case {c.case_id} — Evidence Integrity Verification Completed ({cnt} files)",
                        status="VERIFIED",
                        timestamp=dt,
                        timestamp_formatted=dt.strftime("%d %b %Y, %H:%M")
                    )
                )

        # 7. Metadata Extractions from CaseTimeline
        meta_events = (
            db.query(CaseTimeline)
            .filter(
                CaseTimeline.case_id.in_(assigned_case_ids),
                CaseTimeline.event.ilike("%metadata%")
            )
            .all()
        )
        for me in meta_events:
            if me.case_id in case_map:
                c = case_map[me.case_id]
                dt = me.created_at
                events.append(
                    AnalysisPulseItem(
                        case_id=c.case_id,
                        case_title=c.title,
                        module="METADATA",
                        event_type="METADATA_EXTRACTED",
                        message=f"Case {c.case_id} — Evidence Metadata Extraction Completed",
                        status="COMPLETED",
                        timestamp=dt,
                        timestamp_formatted=dt.strftime("%d %b %Y, %H:%M") if dt else None
                    )
                )

        # Apply module filter if supplied
        if isinstance(module, str) and module.strip() and module.strip().upper() != "ALL":
            target_mod = module.strip().upper()
            events = [e for e in events if e.module.upper() == target_mod]

        # Sort chronologically descending (newest first)
        events.sort(
            key=lambda x: (x.timestamp.timestamp() if x.timestamp.tzinfo is None else x.timestamp.replace(tzinfo=timezone.utc).timestamp()),
            reverse=True
        )

        total = len(events)
        total_pages = (total + limit - 1) // limit if limit > 0 else 1
        offset = (max(1, page) - 1) * limit
        page_items = events[offset:offset + limit]

        return AnalysisPulsePage(
            total=total,
            page=page,
            limit=limit,
            total_pages=total_pages,
            items=page_items
        )
