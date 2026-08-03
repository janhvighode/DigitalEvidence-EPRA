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
from routes.role import router as role_router
from routes.location import router as location_router
from routes.registration import router as registration_router
from routes.cyber_cell import router as cyber_cell_router
from routes.admin import router as admin_router
from routes.change_password import router as change_password_router
from routes.login import router as login_router
from models.password_reset_otp import PasswordResetOTP
from routes.forgot_password import router as forgot_password_router
from routes.dashboard import router as dashboard_router


app = FastAPI(
    title="Smart Digital Evidence Prioritization System API"
)

# Create all database tables
Base.metadata.create_all(bind=engine)

# Register API routes
app.include_router(auth_router)
app.include_router(role_router)
app.include_router(location_router)
app.include_router(registration_router)
app.include_router(cyber_cell_router)
app.include_router(admin_router)
app.include_router(change_password_router)
app.include_router(login_router)
app.include_router(forgot_password_router)
app.include_router(dashboard_router)

@app.get("/")
def home():
    return {
        "message": "Welcome to Smart Digital Evidence Prioritization System"
    }