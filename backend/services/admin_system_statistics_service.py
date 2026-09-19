"""
Admin System Statistics Service.
Provides high-performance, strictly scoped dynamic aggregations over TiDB Cloud.
Zero new tables, zero mock data, zero hardcoded KPIs.

Key Forensic Rules Enforced:
1. EPRA Latest-Result Selection: Exactly ONE latest EPRA result evaluated per evidence item.
2. EPRA Analysis Coverage: Only 'COMPLETE' analysis status counts toward coverage.
3. CBIR Match Metrics: Exact duplicates kept strictly separate from visual similarity.
   Visual matches strictly exclude 'No Significant Visual Match' and 'Weak Visual Resemblance'.
4. Genuine Case Closure: Closure timestamps extracted from CaseTimeline events with fallback to updated_at.
5. Cyber Cell Scoping: Every case and child forensic entity is strictly isolated to current_user.cyber_cell_id.
"""
from datetime import date, datetime, timedelta
from typing import Dict, List, Optional, Set, Tuple
from fastapi import HTTPException, status
from sqlalchemy import func, or_, and_
from sqlalchemy.orm import Session, aliased

from models.case import Case
from models.user import User
from models.evidence import Evidence
from models.epra_result import EPRAResult
from models.cbir_result import CBIRResult
from models.case_timeline import CaseTimeline
from models.evidence_hash import EvidenceHash
from models.evidence_record import EvidenceRecord
from models.possible_entity import PossibleEntity
from models.evidence_link import EvidenceLink
from models.report_record import ReportRecord

from schemas.admin_system_statistics import (
    EPRAStatisticsResponse,
    CBIRStatisticsResponse,
    InvestigatorPerformanceItem,
    InvestigatorStatisticsResponse,
    CaseTrendBucket,
    CaseTrendResponse,
    PriorityAnalysisResponse,
    ForensicSummaryResponse,
    AdminSystemStatisticsSummaryResponse,
)


class AdminSystemStatisticsService:
    """Canonical aggregation service for Administrator System Statistics."""

    # =========================================================================
    # CYBER CELL SCOPING HELPERS
    # =========================================================================

    @staticmethod
    def get_scoped_cases(db: Session, current_user: User) -> List[Case]:
        """
        Retrieve all cases belonging to the Administrator's Cyber Cell branch.
        Uses canonical project pattern: Case.created_by belongs to user with current_user.cyber_cell_id.
        """
        if current_user.cyber_cell_id is None:
            # Fallback for root/system admin without specific branch
            return db.query(Case).all()

        Creator = aliased(User)
        return (
            db.query(Case)
            .join(Creator, Case.created_by == Creator.id)
            .filter(Creator.cyber_cell_id == current_user.cyber_cell_id)
            .all()
        )

    @classmethod
    def get_scoped_case_ids(cls, db: Session, current_user: User) -> Tuple[List[int], List[str]]:
        """Return both integer IDs and string identifiers (case_id and str(id)) for child queries."""
        cases = cls.get_scoped_cases(db, current_user)
        int_ids = [c.id for c in cases]
        str_ids: List[str] = []
        for c in cases:
            str_ids.append(str(c.id))
            if c.case_id and c.case_id not in str_ids:
                str_ids.append(c.case_id)
        return int_ids, str_ids

    @staticmethod
    def _parse_date_range(start_date: Optional[date], end_date: Optional[date]) -> Tuple[Optional[datetime], Optional[datetime]]:
        """
        Convert optional date bounds to [start_dt, end_dt_exclusive) bounds.
        start_dt: beginning of start_date (00:00:00)
        end_dt_exclusive: beginning of day after end_date (00:00:00)
        Semantics: timestamp >= start_dt AND timestamp < end_dt_exclusive.
        """
        if start_date and end_date and start_date > end_date:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="start_date must be before or equal to end_date"
            )
        start_dt = datetime.combine(start_date, datetime.min.time()) if start_date else None
        end_dt_exclusive = datetime.combine(end_date + timedelta(days=1), datetime.min.time()) if end_date else None
        return start_dt, end_dt_exclusive

    # =========================================================================
    # 1. EPRA ANALYTICS
    # =========================================================================

    @classmethod
    def get_epra_statistics(
        cls,
        db: Session,
        current_user: User,
        start_date: Optional[date] = None,
        end_date: Optional[date] = None
    ) -> EPRAStatisticsResponse:
        """
        Aggregates EPRA metrics using ONE latest EPRA result per evidence item.
        Only analysis_status == 'COMPLETE' is treated as fully analyzed for coverage.
        Scores remain strictly on genuine 0.0 - 100.0 scale.
        """
        case_ids, _ = cls.get_scoped_case_ids(db, current_user)
        if not case_ids:
            return EPRAStatisticsResponse(
                coverage_percentage=0.0,
                total_evidence=0,
                analyzed_evidence=0,
                completed_analysis=0,
                partial_analysis=0,
                pending_analysis=0,
                average_epra_score=None,
                highest_score=None,
                lowest_score=None,
                priority_distribution={
                    "CRITICAL": 0, "HIGH": 0, "MEDIUM": 0, "LOW": 0, "VERY LOW": 0, "PENDING": 0
                }
            )

        start_dt, end_dt_exclusive = cls._parse_date_range(start_date, end_date)

        # 1. Total unique evidence items applicable in branch cases
        applicable_evidence_query = db.query(Evidence).filter(Evidence.case_id.in_(case_ids))
        branch_evidence_ids = [e.id for e in applicable_evidence_query.all()]

        if not branch_evidence_ids:
            return EPRAStatisticsResponse(
                coverage_percentage=0.0,
                total_evidence=0,
                analyzed_evidence=0,
                completed_analysis=0,
                partial_analysis=0,
                pending_analysis=0,
                average_epra_score=None,
                highest_score=None,
                lowest_score=None,
                priority_distribution={
                    "CRITICAL": 0, "HIGH": 0, "MEDIUM": 0, "LOW": 0, "VERY LOW": 0, "PENDING": 0
                }
            )

        # 2. Latest EPRA result per evidence_id subquery using MAX(id)
        latest_subq = (
            db.query(
                EPRAResult.evidence_id,
                func.max(EPRAResult.id).label("max_id")
            )
            .filter(EPRAResult.evidence_id.in_(branch_evidence_ids))
        )
        if start_dt:
            latest_subq = latest_subq.filter(
                func.coalesce(EPRAResult.processed_at, EPRAResult.created_at) >= start_dt
            )
        if end_dt_exclusive:
            latest_subq = latest_subq.filter(
                func.coalesce(EPRAResult.processed_at, EPRAResult.created_at) < end_dt_exclusive
            )
        latest_subq = latest_subq.group_by(EPRAResult.evidence_id).subquery()

        # 3. Retrieve the distinct current/latest EPRA records
        latest_results: List[EPRAResult] = (
            db.query(EPRAResult)
            .join(latest_subq, EPRAResult.id == latest_subq.c.max_id)
            .all()
        )

        analyzed_count = len(latest_results)
        completed_count = sum(1 for r in latest_results if r.analysis_status == "COMPLETE")
        partial_count = sum(1 for r in latest_results if r.analysis_status == "PARTIAL / PENDING INPUTS")

        # When date range is specified, total_evidence considers evidence in that scope
        if start_dt or end_dt_exclusive:
            scoped_ev_query = db.query(Evidence.id).filter(Evidence.case_id.in_(case_ids))
            if start_dt:
                scoped_ev_query = scoped_ev_query.filter(Evidence.created_at >= start_dt)
            if end_dt_exclusive:
                scoped_ev_query = scoped_ev_query.filter(Evidence.created_at < end_dt_exclusive)
            created_in_range = set(r[0] for r in scoped_ev_query.all())
            analyzed_in_range = set(r.evidence_id for r in latest_results)
            period_evidence_ids = created_in_range | analyzed_in_range
            total_evidence = len(period_evidence_ids)
        else:
            total_evidence = len(branch_evidence_ids)

        pending_count = max(0, total_evidence - completed_count)

        # Coverage formula: completed / total * 100
        coverage = round((completed_count / total_evidence) * 100, 2) if total_evidence > 0 else 0.0

        # Score calculations on 0.0 - 100.0 scale
        scores = [r.epra_score for r in latest_results if r.epra_score is not None]
        avg_score = round(float(sum(scores) / len(scores)), 2) if scores else None
        high_score = round(float(max(scores)), 2) if scores else None
        low_score = round(float(min(scores)), 2) if scores else None

        # Priority distribution across latest results
        priority_dist = {
            "CRITICAL": 0,
            "HIGH": 0,
            "MEDIUM": 0,
            "LOW": 0,
            "VERY LOW": 0,
            "PENDING": 0
        }
        for r in latest_results:
            p = (r.priority or "").upper().strip().replace("_", " ")
            if p in priority_dist:
                priority_dist[p] += 1
            elif p:
                priority_dist[p] = priority_dist.get(p, 0) + 1
            else:
                priority_dist["PENDING"] += 1

        # Evidence items without any EPRA run in the period are added to PENDING
        unprocessed_evidence = max(0, total_evidence - analyzed_count)
        priority_dist["PENDING"] += unprocessed_evidence

        return EPRAStatisticsResponse(
            coverage_percentage=coverage,
            total_evidence=total_evidence,
            analyzed_evidence=analyzed_count,
            completed_analysis=completed_count,
            partial_analysis=partial_count,
            pending_analysis=pending_count,
            average_epra_score=avg_score,
            highest_score=high_score,
            lowest_score=low_score,
            priority_distribution=priority_dist
        )

    # =========================================================================
    # 2. CBIR STATISTICS
    # =========================================================================

    @classmethod
    def get_cbir_statistics(
        cls,
        db: Session,
        current_user: User,
        start_date: Optional[date] = None,
        end_date: Optional[date] = None
    ) -> CBIRStatisticsResponse:
        """
        Aggregates CBIR statistics scoped to the Cyber Cell.
        Keeps SHA exact duplicates strictly separate from visual similarity scores.
        Meaningful visual matches strictly exclude 'No Significant Visual Match' and 'Weak Visual Resemblance'.
        """
        case_ids, _ = cls.get_scoped_case_ids(db, current_user)
        default_classes = {
            "Exact Duplicate": 0,
            "Very Strong Visual Match": 0,
            "Strong Visual Match": 0,
            "Possible Visual Resemblance": 0,
            "Weak Visual Resemblance": 0,
            "No Significant Visual Match": 0
        }

        if not case_ids:
            return CBIRStatisticsResponse(
                total_comparisons=0,
                cases_with_cbir=0,
                images_analyzed=0,
                exact_duplicates=0,
                visual_matches=0,
                match_rate=0.0,
                average_visual_similarity=None,
                highest_visual_similarity=None,
                classification_distribution=default_classes,
                latest_analysis_at=None
            )

        start_dt, end_dt_exclusive = cls._parse_date_range(start_date, end_date)

        cbir_query = db.query(CBIRResult).filter(CBIRResult.case_id.in_(case_ids))
        if start_dt:
            cbir_query = cbir_query.filter(CBIRResult.created_at >= start_dt)
        if end_dt_exclusive:
            cbir_query = cbir_query.filter(CBIRResult.created_at < end_dt_exclusive)

        records: List[CBIRResult] = cbir_query.all()
        total_comp = len(records)

        if total_comp == 0:
            return CBIRStatisticsResponse(
                total_comparisons=0,
                cases_with_cbir=0,
                images_analyzed=0,
                exact_duplicates=0,
                visual_matches=0,
                match_rate=0.0,
                average_visual_similarity=None,
                highest_visual_similarity=None,
                classification_distribution=default_classes,
                latest_analysis_at=None
            )

        cases_with_cbir = len(set(r.case_id for r in records))
        analyzed_images = len(set(r.query_evidence_id for r in records) | set(r.candidate_evidence_id for r in records))
        exact_dups = sum(1 for r in records if r.sha256_exact_duplicate)

        # Classification counts
        class_dist = dict(default_classes)
        for r in records:
            c = r.classification
            if c in class_dist:
                class_dist[c] += 1
            else:
                class_dist[c] = class_dist.get(c, 0) + 1

        # Meaningful visual matches (excluding Weak Visual Resemblance and No Significant Visual Match)
        meaningful_match_classes = {"Very Strong Visual Match", "Strong Visual Match", "Possible Visual Resemblance"}
        visual_matches = sum(1 for r in records if r.classification in meaningful_match_classes and not r.sha256_exact_duplicate)

        # Match rate: visual matches / total comparisons
        match_rate = round((visual_matches / total_comp) * 100, 2)

        # Visual similarity metrics (0.0 to 1.0)
        vis_scores = [r.visual_similarity_score for r in records if r.visual_similarity_score is not None and not r.sha256_exact_duplicate]
        avg_vis = round(float(sum(vis_scores) / len(vis_scores)), 4) if vis_scores else None
        high_vis = round(float(max(vis_scores)), 4) if vis_scores else None

        latest_record = max(records, key=lambda r: r.created_at if r.created_at else datetime.min)
        latest_ts = latest_record.created_at.isoformat() if latest_record.created_at else None

        return CBIRStatisticsResponse(
            total_comparisons=total_comp,
            cases_with_cbir=cases_with_cbir,
            images_analyzed=analyzed_images,
            exact_duplicates=exact_dups,
            visual_matches=visual_matches,
            match_rate=match_rate,
            average_visual_similarity=avg_vis,
            highest_visual_similarity=high_vis,
            classification_distribution=class_dist,
            latest_analysis_at=latest_ts
        )

    # =========================================================================
    # 3. INVESTIGATOR OPERATIONAL STATISTICS
    # =========================================================================

    @classmethod
    def get_investigator_performance(
        cls,
        db: Session,
        current_user: User,
        start_date: Optional[date] = None,
        end_date: Optional[date] = None
    ) -> InvestigatorStatisticsResponse:
        """
        Operational metrics for investigators belonging to the Administrator's Cyber Cell.
        Completion ratio is derived purely from (Closed / Assigned * 100).
        Zero subjective rankings or arbitrary scores.
        """
        case_ids, _ = cls.get_scoped_case_ids(db, current_user)

        # Fetch active investigators in current Cyber Cell
        investigators_query = db.query(User).filter(
            User.role_id == 2,
            User.is_active == True
        )
        if current_user.cyber_cell_id is not None:
            investigators_query = investigators_query.filter(User.cyber_cell_id == current_user.cyber_cell_id)

        investigators = investigators_query.order_by(User.full_name.asc()).all()

        if not investigators:
            return InvestigatorStatisticsResponse(
                total_investigators=0,
                active_investigators=0,
                average_assigned_cases=0.0,
                top_completion_ratio=0.0,
                investigators=[]
            )

        start_dt, end_dt_exclusive = cls._parse_date_range(start_date, end_date)

        items: List[InvestigatorPerformanceItem] = []

        for inv in investigators:
            # Query investigator cases scoped to the branch with date filtering
            inv_cases_query = db.query(Case).filter(
                Case.investigator_id == inv.id,
                Case.id.in_(case_ids) if case_ids else False
            )
            if start_dt:
                inv_cases_query = inv_cases_query.filter(Case.created_at >= start_dt)
            if end_dt_exclusive:
                inv_cases_query = inv_cases_query.filter(Case.created_at < end_dt_exclusive)

            assigned_cases = inv_cases_query.count()
            completed_cases = inv_cases_query.filter(Case.status == "Closed").count()
            active_cases = assigned_cases - completed_cases

            completion_ratio = round((completed_cases / assigned_cases) * 100, 2) if assigned_cases > 0 else 0.0

            # Associated evidence count in date range
            assigned_case_ids = [c.id for c in inv_cases_query.all()]
            if assigned_case_ids:
                ev_query = db.query(Evidence).filter(Evidence.case_id.in_(assigned_case_ids))
                if start_dt:
                    ev_query = ev_query.filter(Evidence.created_at >= start_dt)
                if end_dt_exclusive:
                    ev_query = ev_query.filter(Evidence.created_at < end_dt_exclusive)
                ev_count = ev_query.count()
            else:
                ev_count = 0

            # Latest case activity from CaseTimeline or Case.updated_at
            latest_activity_ts: Optional[datetime] = None
            if assigned_case_ids:
                tl_query = (
                    db.query(CaseTimeline.created_at)
                    .filter(CaseTimeline.case_id.in_(assigned_case_ids))
                )
                if start_dt:
                    tl_query = tl_query.filter(CaseTimeline.created_at >= start_dt)
                if end_dt_exclusive:
                    tl_query = tl_query.filter(CaseTimeline.created_at < end_dt_exclusive)
                latest_tl = tl_query.order_by(CaseTimeline.created_at.desc()).first()
                if latest_tl and latest_tl[0]:
                    latest_activity_ts = latest_tl[0]

            latest_activity_str = latest_activity_ts.isoformat() if latest_activity_ts else None

            items.append(
                InvestigatorPerformanceItem(
                    investigator_id=inv.id,
                    investigator_name=inv.full_name,
                    assigned_cases=assigned_cases,
                    active_cases=active_cases,
                    completed_cases=completed_cases,
                    evidence_count=ev_count,
                    completion_ratio=completion_ratio,
                    latest_case_activity=latest_activity_str
                )
            )

        total_inv = len(items)
        active_inv = sum(1 for it in items if it.assigned_cases > 0)
        avg_assigned = round(sum(it.assigned_cases for it in items) / total_inv, 2) if total_inv > 0 else 0.0
        active_ratios = [it.completion_ratio for it in items if it.assigned_cases > 0]
        top_completion = max(active_ratios, default=0.0)

        return InvestigatorStatisticsResponse(
            total_investigators=total_inv,
            active_investigators=active_inv,
            average_assigned_cases=avg_assigned,
            top_completion_ratio=top_completion,
            investigators=items
        )

    # =========================================================================
    # 4. CASE PROGRESS TREND
    # =========================================================================

    @classmethod
    def get_case_progress_trend(
        cls,
        db: Session,
        current_user: User,
        start_date: Optional[date] = None,
        end_date: Optional[date] = None
    ) -> CaseTrendResponse:
        """
        Month-by-month progress trend of registered vs genuinely closed cases.
        Uses CaseTimeline closure events where available, with fallback to Case.updated_at for Closed cases.
        """
        cases = cls.get_scoped_cases(db, current_user)
        case_ids = [c.id for c in cases]

        now = datetime.utcnow()
        start_of_month = datetime(now.year, now.month, 1)

        cases_this_month = sum(
            1 for c in cases if c.created_at and c.created_at >= start_of_month
        )

        if not cases:
            return CaseTrendResponse(
                cases_this_month=0,
                total_cases_in_period=0,
                trends=[]
            )

        start_dt, end_dt_exclusive = cls._parse_date_range(start_date, end_date)

        # If no start date given, default to trailing 6 months
        if not start_dt:
            # 5 months ago first day
            year = now.year
            month = now.month - 5
            while month <= 0:
                month += 12
                year -= 1
            start_dt = datetime(year, month, 1)
        if not end_dt_exclusive:
            end_dt = now
        else:
            end_dt = end_dt_exclusive - timedelta(microseconds=1)

        # Generate list of month keys (YYYY-MM) in range
        month_keys: List[str] = []
        cur_year = start_dt.year
        cur_month = start_dt.month
        target_year = end_dt.year
        target_month = end_dt.month

        while (cur_year < target_year) or (cur_year == target_year and cur_month <= target_month):
            month_keys.append(f"{cur_year:04d}-{cur_month:02d}")
            cur_month += 1
            if cur_month > 12:
                cur_month = 1
                cur_year += 1

        # Fetch closure events from CaseTimeline for genuine closure tracking
        closure_events = (
            db.query(CaseTimeline.case_id, CaseTimeline.created_at)
            .filter(
                CaseTimeline.case_id.in_(case_ids),
                or_(
                    CaseTimeline.event.ilike("%Closed%"),
                    CaseTimeline.event.ilike("%Case Closed%"),
                    CaseTimeline.event.ilike("%Status Changed to Closed%")
                )
            )
            .all()
        )
        case_closure_map: Dict[int, datetime] = {}
        for c_id, ts in closure_events:
            if ts and (c_id not in case_closure_map or ts < case_closure_map[c_id]):
                case_closure_map[c_id] = ts

        # Fallback for closed cases without explicit timeline closure event
        for c in cases:
            if c.status == "Closed" and c.id not in case_closure_map:
                case_closure_map[c.id] = c.updated_at or c.created_at or now

        # Compute counts per bucket
        created_per_month: Dict[str, int] = {m: 0 for m in month_keys}
        closed_per_month: Dict[str, int] = {m: 0 for m in month_keys}

        for c in cases:
            if c.created_at:
                k = c.created_at.strftime("%Y-%m")
                if k in created_per_month:
                    created_per_month[k] += 1

            if c.id in case_closure_map:
                cl_ts = case_closure_map[c.id]
                k = cl_ts.strftime("%Y-%m")
                if k in closed_per_month:
                    closed_per_month[k] += 1

        # Running active open caseload estimation per period
        trends: List[CaseTrendBucket] = []
        running_active = 0

        for m in month_keys:
            cr = created_per_month[m]
            cl = closed_per_month[m]
            running_active = max(0, running_active + cr - cl)
            trends.append(
                CaseTrendBucket(
                    period=m,
                    created_cases=cr,
                    closed_cases=cl,
                    active_cases=running_active
                )
            )

        total_in_period = sum(created_per_month.values())

        return CaseTrendResponse(
            cases_this_month=cases_this_month,
            total_cases_in_period=total_in_period,
            trends=trends
        )

    # =========================================================================
    # 5. PRIORITY ANALYSIS
    # =========================================================================

    @classmethod
    def get_priority_analysis(
        cls,
        db: Session,
        current_user: User,
        start_date: Optional[date] = None,
        end_date: Optional[date] = None
    ) -> PriorityAnalysisResponse:
        """
        Returns Case Triage Priority and EPRA Evidence Priority strictly separated.
        Uses database-side SQL filtering for case priorities.
        """
        start_dt, end_dt_exclusive = cls._parse_date_range(start_date, end_date)

        # 1. Case priority distribution - database-side filtering
        case_ids, _ = cls.get_scoped_case_ids(db, current_user)
        case_priorities = {"Critical": 0, "High": 0, "Medium": 0, "Low": 0}

        if case_ids:
            case_query = db.query(Case.priority).filter(Case.id.in_(case_ids))
            if start_dt:
                case_query = case_query.filter(Case.created_at >= start_dt)
            if end_dt_exclusive:
                case_query = case_query.filter(Case.created_at < end_dt_exclusive)

            for (p,) in case_query.all():
                norm_p = (p or "").strip().capitalize()
                if norm_p in case_priorities:
                    case_priorities[norm_p] += 1
                elif norm_p:
                    case_priorities[norm_p] = case_priorities.get(norm_p, 0) + 1

        # 2. EPRA evidence priority distribution (from latest EPRA results)
        epra_stats = cls.get_epra_statistics(db, current_user, start_date, end_date)
        evidence_priorities = epra_stats.priority_distribution

        return PriorityAnalysisResponse(
            case_priority_distribution=case_priorities,
            evidence_epra_priority_distribution=evidence_priorities
        )

    # =========================================================================
    # 6. FORENSIC MODULE SUMMARY
    # =========================================================================

    @classmethod
    def get_forensic_summary(
        cls,
        db: Session,
        current_user: User,
        start_date: Optional[date] = None,
        end_date: Optional[date] = None
    ) -> ForensicSummaryResponse:
        """
        Aggregates operational counts for child forensic modules:
        Integrity, Metadata, Possible Entities, Relationships, and Reports.
        Strictly scoped through Cyber Cell cases and filtered by date range.
        """
        case_ids, case_str_ids = cls.get_scoped_case_ids(db, current_user)

        if not case_ids:
            return ForensicSummaryResponse(
                integrity_verified=0,
                integrity_tampered=0,
                integrity_pending=0,
                total_hashes=0,
                metadata_processed=0,
                metadata_pending=0,
                total_metadata_records=0,
                suspect_entities_count=0,
                cases_with_suspects=0,
                total_evidence_links=0,
                cases_with_links=0,
                reports_generated=0,
                cases_with_reports=0
            )

        start_dt, end_dt_exclusive = cls._parse_date_range(start_date, end_date)

        # 1. Evidence Hashes (Integrity)
        branch_evidence_ids = [
            e.id for e in db.query(Evidence.id).filter(Evidence.case_id.in_(case_ids)).all()
        ]
        if branch_evidence_ids:
            hash_q = db.query(EvidenceHash).filter(EvidenceHash.evidence_id.in_(branch_evidence_ids))
            if start_dt:
                hash_q = hash_q.filter(func.coalesce(EvidenceHash.verified_at, EvidenceHash.created_at) >= start_dt)
            if end_dt_exclusive:
                hash_q = hash_q.filter(func.coalesce(EvidenceHash.verified_at, EvidenceHash.created_at) < end_dt_exclusive)
            hashes = hash_q.all()
            total_hashes = len(hashes)
            verified = sum(1 for h in hashes if h.hash_match is True and not h.tampered)
            tampered = sum(1 for h in hashes if h.tampered is True or h.hash_match is False)
            pending_integrity = total_hashes - verified - tampered
        else:
            total_hashes = verified = tampered = pending_integrity = 0

        # 2. Evidence Records (Metadata)
        if case_str_ids:
            meta_q = db.query(EvidenceRecord).filter(EvidenceRecord.case_id.in_(case_str_ids))
            if start_dt:
                meta_q = meta_q.filter(func.coalesce(EvidenceRecord.uploaded_at, EvidenceRecord.created_at) >= start_dt)
            if end_dt_exclusive:
                meta_q = meta_q.filter(func.coalesce(EvidenceRecord.uploaded_at, EvidenceRecord.created_at) < end_dt_exclusive)
            metadata_records = meta_q.all()
            total_meta = len(metadata_records)
            meta_processed = sum(1 for m in metadata_records if m.processing_status == "PROCESSED")
            meta_pending = total_meta - meta_processed
        else:
            total_meta = meta_processed = meta_pending = 0

        # 3. Possible Entities (Suspect Ranking)
        entity_q = db.query(PossibleEntity).filter(PossibleEntity.case_id.in_(case_ids))
        if start_dt:
            entity_q = entity_q.filter(PossibleEntity.created_at >= start_dt)
        if end_dt_exclusive:
            entity_q = entity_q.filter(PossibleEntity.created_at < end_dt_exclusive)
        entities = entity_q.all()
        total_entities = len(entities)
        cases_with_suspects = len(set(e.case_id for e in entities))

        # 4. Evidence Links (Relationships)
        link_q = db.query(EvidenceLink).filter(EvidenceLink.case_id.in_(case_ids))
        if start_dt:
            link_q = link_q.filter(EvidenceLink.created_at >= start_dt)
        if end_dt_exclusive:
            link_q = link_q.filter(EvidenceLink.created_at < end_dt_exclusive)
        links = link_q.all()
        total_links = len(links)
        cases_with_links = len(set(l.case_id for l in links))

        # 5. Technical Reports
        if case_str_ids:
            rep_q = db.query(ReportRecord).filter(ReportRecord.case_id.in_(case_str_ids))
            if start_dt:
                rep_q = rep_q.filter(ReportRecord.generated_at >= start_dt)
            if end_dt_exclusive:
                rep_q = rep_q.filter(ReportRecord.generated_at < end_dt_exclusive)
            reports = rep_q.all()
            total_reports = len(reports)
            cases_with_reports = len(set(r.case_id for r in reports))
        else:
            total_reports = cases_with_reports = 0

        return ForensicSummaryResponse(
            integrity_verified=verified,
            integrity_tampered=tampered,
            integrity_pending=pending_integrity,
            total_hashes=total_hashes,
            metadata_processed=meta_processed,
            metadata_pending=meta_pending,
            total_metadata_records=total_meta,
            suspect_entities_count=total_entities,
            cases_with_suspects=cases_with_suspects,
            total_evidence_links=total_links,
            cases_with_links=cases_with_links,
            reports_generated=total_reports,
            cases_with_reports=cases_with_reports
        )

    # =========================================================================
    # 7. EXECUTIVE OVERALL SUMMARY
    # =========================================================================

    @classmethod
    def get_system_statistics_summary(
        cls,
        db: Session,
        current_user: User,
        start_date: Optional[date] = None,
        end_date: Optional[date] = None
    ) -> AdminSystemStatisticsSummaryResponse:
        """
        Consolidates top-level executive metrics for dashboard summary cards.
        Properly filters scoped cases and child sections by date range.
        """
        epra = cls.get_epra_statistics(db, current_user, start_date, end_date)
        cbir = cls.get_cbir_statistics(db, current_user, start_date, end_date)
        inv = cls.get_investigator_performance(db, current_user, start_date, end_date)
        trend = cls.get_case_progress_trend(db, current_user, start_date, end_date)
        forensic = cls.get_forensic_summary(db, current_user, start_date, end_date)

        start_dt, end_dt_exclusive = cls._parse_date_range(start_date, end_date)

        cases = cls.get_scoped_cases(db, current_user)
        if start_dt:
            cases = [c for c in cases if c.created_at and c.created_at >= start_dt]
        if end_dt_exclusive:
            cases = [c for c in cases if c.created_at and c.created_at < end_dt_exclusive]

        total_cases = len(cases)
        closed_cases = sum(1 for c in cases if c.status == "Closed")
        active_cases = total_cases - closed_cases

        return AdminSystemStatisticsSummaryResponse(
            epra_coverage_percentage=epra.coverage_percentage,
            total_evidence=epra.total_evidence,
            epra_completed_evidence=epra.completed_analysis,
            pending_epra_analysis=epra.pending_analysis,
            average_epra_score=epra.average_epra_score,
            cbir_total_comparisons=cbir.total_comparisons,
            cbir_exact_duplicates=cbir.exact_duplicates,
            cbir_visual_matches=cbir.visual_matches,
            cbir_match_rate=cbir.match_rate,
            cases_this_month=trend.cases_this_month,
            total_cases=total_cases,
            active_cases=active_cases,
            closed_cases=closed_cases,
            total_investigators=inv.total_investigators,
            active_investigators=inv.active_investigators,
            top_investigator_completion_ratio=inv.top_completion_ratio,
            forensic_summary=forensic
        )
