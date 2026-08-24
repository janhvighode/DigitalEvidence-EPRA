from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from database.database import get_db
from schemas.case import CaseCreate
from services.case_service import create_case

from fastapi import APIRouter, Depends, HTTPException
from models.user import User
from utils.current_user import get_current_user

router = APIRouter(
    prefix="/cases",
    tags=["Cases"]
)

# Temporary Administrator ID
ADMIN_ID = 1


@router.post("/")
def create_new_case(
    case: CaseCreate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):

    if current_user.role_id != 1:
        raise HTTPException(
            status_code=403,
            detail="Administrator access required"
        )

    return create_case(
        db,
        case,
        current_user
    )