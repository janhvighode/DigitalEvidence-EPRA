from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from database.database import get_db
from services.location_service import get_all_locations

router = APIRouter(
    prefix="/locations",
    tags=["Locations"]
)


@router.get("/")
def fetch_locations(db: Session = Depends(get_db)):
    return get_all_locations(db)