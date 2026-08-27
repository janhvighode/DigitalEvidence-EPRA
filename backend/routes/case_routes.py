from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from database.database import get_db
from schemas.case import CaseCreate
from services.case_service import create_case

router = APIRouter(
    prefix="/cases",
    tags=["Cases"]
)

# Temporary Administrator ID
ADMIN_ID = 1


@router.post("/")
def create_new_case(case: CaseCreate, db: Session = Depends(get_db)):
    return create_case(db, case, ADMIN_ID)