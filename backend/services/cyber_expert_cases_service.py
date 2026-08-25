from sqlalchemy.orm import Session, aliased
from sqlalchemy import or_

from models.case import Case
from models.user import User


def get_my_cases(
    db: Session,
    current_user: User,
    search: str | None = None,
    status: str | None = None,
    priority: str | None = None,
    page: int = 1,
    limit: int = 10
):

    Investigator = aliased(User)

    # ------------------------------------------
    # STEP 1: ONLY LOGGED-IN CYBER EXPERT CASES
    # ------------------------------------------

    query = (
        db.query(
            Case,
            Investigator.full_name.label(
                "investigator_name"
            )
        )
        .outerjoin(
            Investigator,
            Case.investigator_id == Investigator.id
        )
        .filter(
            Case.cyber_expert_id == current_user.id
        )
    )

    # ------------------------------------------
    # STEP 2: SEARCH
    # ------------------------------------------

    if search:

        query = query.filter(
            or_(
                Case.case_id.ilike(
                    f"%{search}%"
                ),
                Case.title.ilike(
                    f"%{search}%"
                ),
                Case.description.ilike(
                    f"%{search}%"
                )
            )
        )

    # ------------------------------------------
    # STEP 3: STATUS FILTER
    # ------------------------------------------

    if status:

        query = query.filter(
            Case.status == status
        )

    # ------------------------------------------
    # STEP 4: PRIORITY FILTER
    # ------------------------------------------

    if priority:

        query = query.filter(
            Case.priority == priority
        )

    # ------------------------------------------
    # STEP 5: TOTAL BEFORE PAGINATION
    # ------------------------------------------

    total = query.count()

    # ------------------------------------------
    # STEP 6: PAGINATION
    # ------------------------------------------

    offset = (page - 1) * limit

    results = (
        query
        .order_by(
            Case.updated_at.desc()
        )
        .offset(offset)
        .limit(limit)
        .all()
    )

    cases = []

    for case, investigator_name in results:

        cases.append({
            "id": case.id,
            "case_id": case.case_id,
            "title": case.title,
            "description": case.description,
            "investigator_name": investigator_name,
            "status": case.status,
            "priority": case.priority,
            "assigned_date": case.created_at,
            "updated_at": case.updated_at
        })

    return {
        "total": total,
        "page": page,
        "limit": limit,
        "cases": cases
    }