from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from database.database import get_db
from services.role_service import get_all_roles

router = APIRouter(
    prefix="/roles",
    tags=["Roles"]
)


@router.get("/")
def fetch_roles(db: Session = Depends(get_db)):
    return get_all_roles(db)