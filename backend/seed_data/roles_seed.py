from database.database import SessionLocal
from models.role import Role

db = SessionLocal()

roles = [
    "Administrator",
    "Investigator",
    "Cyber Expert"
]

for role_name in roles:
    existing_role = db.query(Role).filter(Role.role_name == role_name).first()

    if not existing_role:
        new_role = Role(role_name=role_name)
        db.add(new_role)

db.commit()
db.close()

print("✅ Default roles inserted successfully.")