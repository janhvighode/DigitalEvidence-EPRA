from sqlalchemy.orm import Session

from models.cyber_cell import CyberCell


def get_cyber_cells_by_city(
    db: Session,
    city_id: int
):

    cyber_cells = db.query(CyberCell).filter(
        CyberCell.city_id == city_id
    ).all()

    result = []

    for cell in cyber_cells:

        result.append(
            {
                "id": cell.id,
                "name": cell.cyber_cell_name
            }
        )

    return result