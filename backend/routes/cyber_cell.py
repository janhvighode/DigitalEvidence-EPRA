from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from database.database import get_db
from services.cyber_cell_service import get_cyber_cells_by_city

router = APIRouter(
    prefix="/cyber-cells",
    tags=["Cyber Cells"]
)


@router.get("/{city_id}")
def fetch_cyber_cells(
    city_id: int,
    db: Session = Depends(get_db)
):
    return get_cyber_cells_by_city(
        db,
        city_id
    )