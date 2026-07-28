from fastapi import FastAPI

from database.database import Base, engine

# Import all models
from models.role import Role
from models.city import City
from models.cyber_cell import CyberCell
from models.registration_request import RegistrationRequest
from models.user import User

# Import routes
from routes.auth import router as auth_router

app = FastAPI(
    title="Smart Digital Evidence Prioritization System API"
)

# Create all database tables
Base.metadata.create_all(bind=engine)

# Register API routes
app.include_router(auth_router)

@app.get("/")
def home():
    return {
        "message": "Welcome to Smart Digital Evidence Prioritization System"
    }