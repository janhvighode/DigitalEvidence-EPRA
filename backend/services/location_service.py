from sqlalchemy.orm import Session

from models.city import City


def get_all_locations(db: Session):

    cities = db.query(City).all()

    result = []

    for city in cities:

        result.append(
            {
                "city_id": city.id,
                "state": "Maharashtra",
                "city_name": city.city_name
            }
        )

    return result