from database.database import SessionLocal
from models.city import City

db = SessionLocal()

cities = [
    "Nagpur",
    "Pune",
    "Mumbai",
    "Nashik",
    "Amravati",
    "Aurangabad",
    "Kolhapur",
    "Solapur"
]

for city_name in cities:
    existing_city = db.query(City).filter(
        City.city_name == city_name
    ).first()

    if not existing_city:
        db.add(
            City(city_name=city_name)
        )

db.commit()
db.close()

print("✅ Default cities inserted successfully.")