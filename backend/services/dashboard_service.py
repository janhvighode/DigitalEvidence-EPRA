from schemas.dashboard import DashboardStats, RecentCase, PrioritySummary


def get_dashboard_stats():
    return DashboardStats(
        total_cases=12,
        evidence_files=48,
        high_priority=15,
        pending_analysis=6
    )


def get_recent_cases():
    return [
        RecentCase(
            case_id="CASE-001",
            title="Online Banking Fraud",
            status="Active"
        ),
        RecentCase(
            case_id="CASE-002",
            title="Data Theft Investigation",
            status="Processing"
        ),
        RecentCase(
            case_id="CASE-003",
            title="Cyber Harassment",
            status="Under Review"
        )
    ]


def get_priority_summary():
    return PrioritySummary(
        high=15,
        medium=20,
        low=13
    )