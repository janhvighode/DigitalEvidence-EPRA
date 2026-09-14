"""
Legacy System Statistics Service.
Refactored to delegate directly to AdminSystemStatisticsService to eliminate duplicate business logic
and remove legacy hardcoded demo values while preserving backward compatibility for legacy routes.
"""
from typing import List, Dict, Any
from sqlalchemy.orm import Session

from models.user import User
from services.admin_system_statistics_service import AdminSystemStatisticsService


def _get_system_context_user(db: Session) -> User:
    """Return a system-level Administrator context for legacy unauthenticated routes."""
    admin = db.query(User).filter(User.role_id == 1).first()
    if admin:
        return admin
    # Fallback in-memory user representing system scope
    u = User()
    u.id = 1
    u.full_name = "System Administrator"
    u.role_id = 1
    u.cyber_cell_id = None
    return u


def get_epra_statistics(db: Session) -> Dict[str, Any]:
    """Legacy wrapper delegating to canonical EPRA aggregation."""
    user = _get_system_context_user(db)
    res = AdminSystemStatisticsService.get_epra_statistics(db, current_user=user)

    return {
        "overall_health": res.coverage_percentage,
        "total_evidence": res.total_evidence,
        "high_priority": res.priority_distribution.get("HIGH", 0),
        "medium_priority": res.priority_distribution.get("MEDIUM", 0),
        "low_priority": res.priority_distribution.get("LOW", 0),
        "pending_analysis": res.pending_analysis,
        "average_epra_score": res.average_epra_score or 0.0,
        "highest_score": res.highest_score or 0.0,
        "lowest_score": res.lowest_score or 0.0,
    }


def get_cbir_statistics(db: Session) -> Dict[str, Any]:
    """Legacy wrapper delegating to canonical CBIR aggregation."""
    user = _get_system_context_user(db)
    res = AdminSystemStatisticsService.get_cbir_statistics(db, current_user=user)

    failed = max(0, res.total_comparisons - res.visual_matches)
    return {
        "total_images": res.images_analyzed,
        "matched_images": res.visual_matches,
        "failed_matches": failed,
        "match_rate": res.match_rate
    }


def get_investigator_performance(db: Session) -> List[Dict[str, Any]]:
    """Legacy wrapper delegating to canonical investigator workload aggregation."""
    user = _get_system_context_user(db)
    res = AdminSystemStatisticsService.get_investigator_performance(db, current_user=user)

    return [
        {
            "investigator_name": item.investigator_name,
            "assigned_cases": item.assigned_cases,
            "completed_cases": item.completed_cases,
            "active_cases": item.active_cases,
            "completion_percentage": item.completion_ratio,
        }
        for item in res.investigators
    ]


def get_case_progress_trend(db: Session) -> List[Dict[str, Any]]:
    """Legacy wrapper delegating to canonical case progress trend aggregation."""
    user = _get_system_context_user(db)
    res = AdminSystemStatisticsService.get_case_progress_trend(db, current_user=user)

    return [
        {
            "month": bucket.period,
            "created_cases": bucket.created_cases,
            "closed_cases": bucket.closed_cases,
        }
        for bucket in res.trends
    ]


def get_priority_analysis(db: Session) -> Dict[str, Any]:
    """Legacy wrapper returning case priority analysis."""
    user = _get_system_context_user(db)
    res = AdminSystemStatisticsService.get_priority_analysis(db, current_user=user)

    return {
        "high_priority": res.case_priority_distribution.get("High", 0),
        "medium_priority": res.case_priority_distribution.get("Medium", 0),
        "low_priority": res.case_priority_distribution.get("Low", 0),
    }