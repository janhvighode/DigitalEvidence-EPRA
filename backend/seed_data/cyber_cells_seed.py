from database.database import SessionLocal
from models.city import City
from models.cyber_cell import CyberCell

db = SessionLocal()

cyber_cells = {
    "Nagpur": [
        "Sadar Cyber Cell",
        "Kamtee Cyber Cell",
        "Sitabuldi Cyber Cell"
    ],
    "Pune": [
        "Shivajinagar Cyber Cell",
        "Hadapsar Cyber Cell"
    ],
    "Mumbai": [
        "Andheri Cyber Cell",
        "Bandra Cyber Cell"
    ],
    "Nashik": [
        "Nashik City Cyber Cell"
    ],
    "Amravati": [
        "Amravati Cyber Cell"
    ],
    "Aurangabad": [
        "Aurangabad Cyber Cell"
    ],
    "Kolhapur": [
        "Kolhapur Cyber Cell"
    ],
    "Solapur": [
        "Solapur Cyber Cell"
    ]
}

for city_name, cells in cyber_cells.items():

    city = db.query(City).filter(
        City.city_name == city_name
    ).first()

    if city:

        for cell in cells:

            existing = db.query(CyberCell).filter(
                CyberCell.cyber_cell_name == cell
            ).first()

            if not existing:

                db.add(
                    CyberCell(
                        cyber_cell_name=cell,
                        address="Not Available",
                        admin_email=f"{cell.lower().replace(' ', '')}@gov.in",
                        city_id=city.id
                    )
                )

db.commit()
db.close()

print("✅ Cyber Cells inserted successfully.")