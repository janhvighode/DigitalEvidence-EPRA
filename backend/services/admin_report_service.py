from pathlib import Path
from typing import Optional, List, Dict, Any, Tuple, Set
from datetime import datetime
from fastapi import HTTPException, status
from sqlalchemy.orm import Session, aliased
from sqlalchemy import or_, and_, func

from models.case import Case
from models.user import User
from models.role import Role
from models.evidence import Evidence
from models.epra_result import EPRAResult
from models.report_record import ReportRecord
from services.pdf_service import DEFAULT_REPORTS_DIR
from services.technical_report_service import format_bytes
from schemas.admin_report import (
    AdminAssignedUser,
    AdminLatestReportItem,
    CaseReportJourney,
    AdminCaseReportItem,
    AdminCaseReportPage,
    AdminReportCoverageResponse,
    AdminReportHistoryItem,
    AdminReportHistoryResponse
)


class AdminReportService:
    """
    Aggregation and reporting service strictly for Administrator case-wise report monitoring.
    Reuses existing ReportRecord, Case, User, and Evidence models without duplicating report generation.
    """

    @staticmethod
    def verify_admin_user(current_user: User) -> None:
        """Verify that the user is an Administrator (role_id == 1)."""
        if not current_user:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Authentication required"
            )
        if current_user.role_id != 1:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Administrator access required"
            )

    @classmethod
    def get_admin_scoped_cases_query(cls, db: Session, current_user: User):
        """
        Base query for cases visible to this Administrator:
        - Reuses the canonical project branch pattern:
          Creator of the case must have creator.cyber_cell_id == current_user.cyber_cell_id.
        - If current_user.cyber_cell_id is None: returns all cases.
        """
        cls.verify_admin_user(current_user)
        query = db.query(Case)

        if current_user.cyber_cell_id is not None:
            Creator = aliased(User)
            query = query.join(
                Creator,
                Case.created_by == Creator.id
            ).filter(
                Creator.cyber_cell_id == current_user.cyber_cell_id
            )

        return query

    @classmethod
    def verify_case_admin_access(cls, db: Session, case_identifier: str | int, current_user: User) -> Case:
        """
        Resolves a case by numeric ID or string case_id, enforcing Admin role and cyber cell scope.
        """
        cls.verify_admin_user(current_user)
        ident_str = str(case_identifier).strip()

        if ident_str.isdigit():
            case = db.query(Case).filter(
                or_(
                    Case.id == int(ident_str),
                    Case.case_id == ident_str
                )
            ).first()
        else:
            case = db.query(Case).filter(
                Case.case_id.ilike(ident_str)
            ).first()

        if not case:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Case '{case_identifier}' not found"
            )

        # Scoping check
        if current_user.cyber_cell_id is not None:
            creator = db.query(User).filter(User.id == case.created_by).first()
            if creator and creator.cyber_cell_id != current_user.cyber_cell_id:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="Access denied: Case does not belong to your authorized cyber cell scope"
                )

        return case

    @staticmethod
    def check_file_available(report: ReportRecord) -> bool:
        """
        Checks if the persistent report binary exists on disk and is non-empty without regenerating.
        """
        if not report:
            return False

        resolved_root = DEFAULT_REPORTS_DIR.parent.resolve()

        if report.file_path:
            try:
                p = Path(report.file_path).resolve()
                if p.is_relative_to(resolved_root) and p.is_file() and p.stat().st_size > 0:
                    return True
            except Exception:
                pass

        candidate_name = report.file_name or (Path(report.file_path).name if report.file_path else None)
        if candidate_name:
            try:
                local_report = (DEFAULT_REPORTS_DIR / candidate_name).resolve()
                if local_report.is_relative_to(resolved_root) and local_report.is_file() and local_report.stat().st_size > 0:
                    return True
                local_manifest = (DEFAULT_REPORTS_DIR.parent / "hash_manifests" / candidate_name).resolve()
                if local_manifest.is_relative_to(resolved_root) and local_manifest.is_file() and local_manifest.stat().st_size > 0:
                    return True
            except Exception:
                pass

        return False

    @classmethod
    def get_case_wise_reports(
        cls,
        db: Session,
        current_user: User,
        search: Optional[str] = None,
        case_status: Optional[str] = None,
        report_status: Optional[str] = None,
        sort: Optional[str] = "recent",
        page: int = 1,
        page_size: int = 10
    ) -> AdminCaseReportPage:
        """
        Returns paginated, searchable, filterable, sortable list of authorized cases
        with report status, report count, latest report, and journey milestones.
        """
        if not isinstance(search, str):
            search = None
        if not isinstance(case_status, str):
            case_status = None
        if not isinstance(report_status, str):
            report_status = None
        if not isinstance(sort, str):
            sort = "recent"
        if not isinstance(page, int):
            page = 1
        if not isinstance(page_size, int):
            page_size = 10

        query = cls.get_admin_scoped_cases_query(db, current_user)

        # 1. Server-side search
        if search and search.strip():
            kw = f"%{search.strip()}%"
            Investigator = aliased(User)
            Expert = aliased(User)
            query = query.outerjoin(
                Investigator,
                Case.investigator_id == Investigator.id
            ).outerjoin(
                Expert,
                Case.cyber_expert_id == Expert.id
            ).filter(
                or_(
                    Case.case_id.ilike(kw),
                    Case.title.ilike(kw),
                    Case.description.ilike(kw),
                    Investigator.full_name.ilike(kw),
                    Expert.full_name.ilike(kw)
                )
            )

        # 2. Filter by Case Status
        if case_status and case_status.strip() and case_status.upper() != "ALL":
            query = query.filter(Case.status == case_status.strip())

        # Retrieve all matched cases for aggregation
        cases = query.all()

        if not cases:
            return AdminCaseReportPage(
                total_items=0,
                total_pages=1,
                page=page,
                page_size=page_size,
                items=[]
            )

        # 3. Batch prefetch to avoid N+1 queries
        case_id_strings: List[str] = []
        case_int_ids: List[int] = []
        user_ids: Set[int] = set()

        for c in cases:
            case_id_strings.append(str(c.case_id))
            case_id_strings.append(str(c.id))
            case_int_ids.append(c.id)
            if c.investigator_id:
                user_ids.add(c.investigator_id)
            if c.cyber_expert_id:
                user_ids.add(c.cyber_expert_id)

        # Prefetch users (investigators and cyber experts)
        users_map = {u.id: u for u in db.query(User).filter(User.id.in_(user_ids)).all()} if user_ids else {}

        # Prefetch report records
        all_reports = db.query(ReportRecord).filter(
            ReportRecord.case_id.in_(case_id_strings)
        ).order_by(ReportRecord.generated_at.desc()).all() if case_id_strings else []

        reports_by_case: Dict[str, List[ReportRecord]] = {}
        for r in all_reports:
            reports_by_case.setdefault(str(r.case_id), []).append(r)

        # Prefetch evidence counts
        evidence_counts = db.query(
            Evidence.case_id,
            func.count(Evidence.id)
        ).filter(Evidence.case_id.in_(case_int_ids)).group_by(Evidence.case_id).all() if case_int_ids else []
        ev_count_map = {row[0]: row[1] for row in evidence_counts}

        # Prefetch analyzed evidence count (EPRAResult.analysis_status == 'COMPLETE')
        analyzed_counts = db.query(
            EPRAResult.case_id,
            func.count(func.distinct(EPRAResult.evidence_id))
        ).filter(
            EPRAResult.case_id.in_(case_int_ids),
            EPRAResult.analysis_status == "COMPLETE"
        ).group_by(EPRAResult.case_id).all() if case_int_ids else []
        analyzed_count_map = {row[0]: row[1] for row in analyzed_counts}

        # 4. Construct case items
        case_items: List[AdminCaseReportItem] = []

        for case in cases:
            # Match reports for both case.case_id and str(case.id)
            matched = (
                reports_by_case.get(str(case.case_id), []) +
                reports_by_case.get(str(case.id), [])
            )
            # Deduplicate by report id while preserving newest-first order
            seen_rep_ids = set()
            unique_reports = []
            for r in matched:
                if r.id not in seen_rep_ids:
                    seen_rep_ids.add(r.id)
                    unique_reports.append(r)

            sorted_reports = sorted(
                unique_reports,
                key=lambda x: x.generated_at or datetime.min,
                reverse=True
            )

            reports_count = len(sorted_reports)
            final_rep = next((r for r in sorted_reports if not r.is_draft), None)
            draft_rep = next((r for r in sorted_reports if r.is_draft), None)

            # Derive canonical report status
            if final_rep:
                r_status = "FINAL" if case.status == "Closed" else "GENERATED"
            elif draft_rep:
                r_status = "DRAFT"
            else:
                r_status = "NOT_GENERATED"

            # Filter by report_status if requested
            if report_status and report_status.strip() and report_status.upper() != "ALL":
                target = report_status.strip().upper()
                if target in ("FINAL", "COMPLETED") and r_status != "FINAL":
                    continue
                elif target in ("GENERATED", "ONGOING") and r_status != "GENERATED":
                    continue
                elif target == "DRAFT" and r_status != "DRAFT":
                    continue
                elif target == "NOT_GENERATED" and r_status != "NOT_GENERATED":
                    continue
                elif r_status != target:
                    continue

            # Latest report metadata
            latest_rep_obj: Optional[AdminLatestReportItem] = None
            if sorted_reports:
                latest = sorted_reports[0]
                latest_status = "DRAFT" if latest.is_draft else ("FINAL" if case.status == "Closed" else "GENERATED")
                file_avail = cls.check_file_available(latest)
                latest_rep_obj = AdminLatestReportItem(
                    report_id=latest.id,
                    report_name=latest.file_name,
                    report_type=latest.report_type,
                    status=latest_status,
                    is_draft=latest.is_draft,
                    generated_at=latest.generated_at,
                    generated_at_formatted=latest.generated_at.strftime("%d %b %Y, %H:%M") if latest.generated_at else None,
                    generated_by_id=latest.generated_by_id,
                    generated_by_name=latest.investigator_name,
                    generated_by_role=latest.generated_by_role,
                    file_available=file_avail,
                    file_format=latest.file_format or "PDF",
                    file_size_bytes=latest.file_size_bytes or 0,
                    file_size_formatted=format_bytes(latest.file_size_bytes or 0),
                    view_url=f"/reports/{latest.id}/view",
                    download_url=f"/reports/{latest.id}/download"
                )

            # Journey milestones
            total_ev = ev_count_map.get(case.id, 0)
            analyzed_ev = analyzed_count_map.get(case.id, 0)
            analysis_done = (analyzed_ev >= total_ev) if total_ev > 0 else None

            journey = CaseReportJourney(
                evidence_collected=(total_ev > 0),
                analysis_completed=analysis_done,
                report_generated=(reports_count > 0),
                finalized=(r_status == "FINAL")
            )

            # Assigned users
            inv_user = users_map.get(case.investigator_id)
            exp_user = users_map.get(case.cyber_expert_id)

            assigned_inv = AdminAssignedUser(
                id=inv_user.id,
                name=inv_user.full_name or inv_user.username,
                role="Investigator"
            ) if inv_user else None

            assigned_exp = AdminAssignedUser(
                id=exp_user.id,
                name=exp_user.full_name or exp_user.username,
                role="Cyber Expert"
            ) if exp_user else None

            case_items.append(
                AdminCaseReportItem(
                    case_id=case.case_id,
                    internal_case_id=case.id,
                    case_title=case.title or f"Case #{case.case_id}",
                    case_priority=case.priority or "Medium",
                    case_status=case.status or "Open",
                    created_at=case.created_at,
                    assigned_investigator=assigned_inv,
                    assigned_cyber_expert=assigned_exp,
                    report_status=r_status,
                    reports_count=reports_count,
                    latest_report=latest_rep_obj,
                    journey=journey
                )
            )

        # 5. Sorting
        sort_key = (sort or "recent").strip().lower()
        if sort_key == "oldest":
            case_items.sort(key=lambda x: x.created_at or datetime.min)
        elif sort_key == "case_id":
            case_items.sort(key=lambda x: str(x.case_id).lower())
        elif sort_key == "latest_report":
            case_items.sort(
                key=lambda x: (
                    x.latest_report.generated_at if x.latest_report and x.latest_report.generated_at else datetime.min
                ),
                reverse=True
            )
        else:  # default "recent"
            case_items.sort(key=lambda x: x.created_at or datetime.min, reverse=True)

        # 6. Pagination
        total_items = len(case_items)
        page_num = max(1, page)
        size = max(1, page_size)
        total_pages = max(1, (total_items + size - 1) // size)
        start_idx = (page_num - 1) * size
        end_idx = start_idx + size
        paged_items = case_items[start_idx:end_idx]

        return AdminCaseReportPage(
            total_items=total_items,
            total_pages=total_pages,
            page=page_num,
            page_size=size,
            items=paged_items
        )

    @classmethod
    def get_report_coverage(cls, db: Session, current_user: User) -> AdminReportCoverageResponse:
        """
        Returns dynamic case-based report coverage for the Admin's authorized cases:
        - total_cases
        - cases_with_reports (cases having at least 1 persisted report)
        - cases_without_reports
        - coverage_percentage: cases_with_reports / total_cases * 100
        - status_counts: distribution of cases by canonical report_status
        """
        cases = cls.get_admin_scoped_cases_query(db, current_user).all()
        total_cases = len(cases)

        if total_cases == 0:
            return AdminReportCoverageResponse(
                total_cases=0,
                cases_with_reports=0,
                cases_without_reports=0,
                coverage_percentage=0.0,
                status_counts={
                    "not_generated": 0,
                    "draft": 0,
                    "generated": 0,
                    "final": 0
                }
            )

        case_id_strings: List[str] = []
        for c in cases:
            case_id_strings.append(str(c.case_id))
            case_id_strings.append(str(c.id))

        reports = db.query(ReportRecord).filter(
            ReportRecord.case_id.in_(case_id_strings)
        ).all() if case_id_strings else []

        reports_by_case: Dict[str, List[ReportRecord]] = {}
        for r in reports:
            reports_by_case.setdefault(str(r.case_id), []).append(r)

        cases_with_reports = 0
        not_generated = 0
        draft = 0
        generated = 0
        final = 0

        for c in cases:
            matched = (
                reports_by_case.get(str(c.case_id), []) +
                reports_by_case.get(str(c.id), [])
            )
            has_reports = len(matched) > 0
            if has_reports:
                cases_with_reports += 1

            final_rep = next((r for r in matched if not r.is_draft), None)
            draft_rep = next((r for r in matched if r.is_draft), None)

            if final_rep:
                if c.status == "Closed":
                    final += 1
                else:
                    generated += 1
            elif draft_rep:
                draft += 1
            else:
                not_generated += 1

        cases_without_reports = total_cases - cases_with_reports
        coverage_pct = round((cases_with_reports / total_cases) * 100.0, 2)

        return AdminReportCoverageResponse(
            total_cases=total_cases,
            cases_with_reports=cases_with_reports,
            cases_without_reports=cases_without_reports,
            coverage_percentage=coverage_pct,
            status_counts={
                "not_generated": not_generated,
                "draft": draft,
                "generated": generated,
                "final": final
            }
        )

    @classmethod
    def get_case_report_overview(
        cls,
        db: Session,
        case_id: str | int,
        current_user: User
    ) -> AdminCaseReportItem:
        """
        Returns a single authorized case's report overview and latest report metadata.
        """
        case = cls.verify_case_admin_access(db, case_id, current_user)
        # Use get_case_wise_reports filtered to this specific case
        page_res = cls.get_case_wise_reports(
            db=db,
            current_user=current_user,
            search=case.case_id,
            page=1,
            page_size=10
        )
        for item in page_res.items:
            if item.internal_case_id == case.id or item.case_id == case.case_id:
                return item

        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Report overview for Case #{case_id} not found"
        )

    @classmethod
    def get_case_report_history(
        cls,
        db: Session,
        case_id: str | int,
        current_user: User
    ) -> AdminReportHistoryResponse:
        """
        Returns all persisted reports for an authorized case, ordered newest -> oldest.
        Includes draft, generated, and final reports without duplicating records.
        """
        case = cls.verify_case_admin_access(db, case_id, current_user)
        match_ids = [str(case.case_id), str(case.id)]

        reports = db.query(ReportRecord).filter(
            ReportRecord.case_id.in_(match_ids)
        ).order_by(ReportRecord.generated_at.desc()).all()

        seen_ids = set()
        history_items: List[AdminReportHistoryItem] = []

        for r in reports:
            if r.id in seen_ids:
                continue
            seen_ids.add(r.id)

            file_avail = cls.check_file_available(r)
            r_status = "DRAFT" if r.is_draft else ("FINAL" if case.status == "Closed" else "GENERATED")

            history_items.append(
                AdminReportHistoryItem(
                    report_id=r.id,
                    report_name=r.file_name,
                    report_type=r.report_type,
                    status=r_status,
                    is_draft=r.is_draft,
                    file_format=r.file_format or "PDF",
                    file_size_bytes=r.file_size_bytes or 0,
                    file_size_formatted=format_bytes(r.file_size_bytes or 0),
                    generated_at=r.generated_at,
                    generated_at_formatted=r.generated_at.strftime("%d %b %Y, %H:%M") if r.generated_at else None,
                    generated_by_id=r.generated_by_id,
                    generated_by_name=r.investigator_name,
                    generated_by_role=r.generated_by_role,
                    file_available=file_avail,
                    view_url=f"/reports/{r.id}/view",
                    download_url=f"/reports/{r.id}/download"
                )
            )

        return AdminReportHistoryResponse(
            case_id=case.case_id,
            internal_case_id=case.id,
            total_reports=len(history_items),
            reports=history_items
        )
