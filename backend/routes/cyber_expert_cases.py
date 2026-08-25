from fastapi import (
    APIRouter,
    Depends,
    HTTPException,
    Query
)

from sqlalchemy.orm import Session

from database.database import get_db

from models.user import User
from utils.current_user import get_current_user

from services.cyber_expert_cases_service import (
    get_my_cases
)

from schemas.cyber_expert_cases import (
    CyberExpertMyCasesPage
)


router = APIRouter(
    prefix="/cyber-expert",
    tags=["Cyber Expert My Cases"]
)


@router.get(
    "/my-cases",
    response_model=CyberExpertMyCasesPage
)
def fetch_my_cases(

    search: str | None = Query(
        default=None
    ),

    status: str | None = Query(
        default=None
    ),

    priority: str | None = Query(
        default=None
    ),

    page: int = Query(
        default=1,
        ge=1
    ),

    limit: int = Query(
        default=10,
        ge=1,
        le=100
    ),

    current_user: User =
        Depends(get_current_user),

    db: Session =
        Depends(get_db)
):

    if current_user.role_id != 3:

        raise HTTPException(
            status_code=403,
            detail="Cyber Expert access required"
        )

    return get_my_cases(
        db=db,
        current_user=current_user,
        search=search,
        status=status,
        priority=priority,
        page=page,
        limit=limit
    )