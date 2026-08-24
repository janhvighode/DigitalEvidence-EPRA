from fastapi import FastAPI

from database.database import Base, engine
from fastapi.middleware.cors import CORSMiddleware

# Import all models
from models.role import Role
from models.city import City
from models.cyber_cell import CyberCell
from models.registration_request import RegistrationRequest
from models.user import User
from models.case import Case

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
from routes.case_routes import router as case_router
from routes.user_management_routes import router as user_management_router
from routes.case_activity_routes import router as case_activity_router
from models.case_timeline import CaseTimeline
from routes.report_routes import router as report_router
from routes.report_routes import router as report_router
from models.notification import Notification
from routes.notification_routes import router as notification_router
from routes.profile_routes import router as profile_router
from models.settings import Settings
from routes.settings_routes import router as settings_router
from models.system_statistics import SystemStatistics
from routes.system_statistics_routes import router as statistics_router
from routes.user_management_routes import router as user_management_router
from routes.cyber_expert_dashboard import router as cyber_expert_dashboard_router


app = FastAPI(
    title="Smart Digital Evidence Prioritization System API"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
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
app.include_router(case_router)
app.include_router(user_management_router)
app.include_router(case_activity_router)
app.include_router(report_router)
app.include_router(report_router)
app.include_router(notification_router)
app.include_router(profile_router)
app.include_router(settings_router)
app.include_router(statistics_router)
app.include_router(user_management_router)
app.include_router(cyber_expert_dashboard_router)

@app.get("/")
def home():
    return {
        "message": "Welcome to Smart Digital Evidence Prioritization System"
    }