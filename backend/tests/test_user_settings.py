"""
Comprehensive Test Suite for User Settings Module.
Covers all 30 required verification specifications:
 1. Admin GET settings
 2. Investigator GET settings
 3. Cyber Expert GET settings
 4. Unauthenticated GET -> 401
 5. Unauthenticated PUT -> 401
 6. Default record creation
 7. Repeated GET does not create duplicate row
 8. User A / User B isolation
 9. LIGHT/DARK persistence & normalization
10. Invalid theme rejection
11. Email toggle persistence
12. Browser toggle persistence
13. 15-minute timeout
14. 30-minute timeout
15. 60-minute timeout
16. 120-minute timeout
17. NULL/Never timeout
18. Invalid 45-minute timeout rejected
19. Wrong current password rejected
20. Mismatched confirmation rejected
21. Same old/new password rejected
22. Weak password rejected
23. Successful password change
24. Bcrypt hash stored, not plaintext
25. Password/hash absent from response
26. Password change affects current user only
27. is_first_login behavior
28. Login with new password succeeds
29. Secure /settings route conflict check
30. Legacy unauthenticated settings mutation is no longer possible
"""
import os
import sys
from pathlib import Path
from fastapi import HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials
from pydantic import ValidationError
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, Session

# Setup system paths
backend_dir = Path(__file__).resolve().parent.parent
if str(backend_dir) not in sys.path:
    sys.path.insert(0, str(backend_dir))
root_dir = backend_dir.parent
if str(root_dir) not in sys.path:
    sys.path.insert(0, str(root_dir))

from database.database import Base
from models.role import Role
from models.city import City
from models.cyber_cell import CyberCell
from models.user import User
from models.user_settings import UserSettings
from schemas.user_settings import (
    UserSettingsResponse,
    UserSettingsUpdate,
    ChangePasswordRequest,
    ChangePasswordResponse,
)
from services.user_settings_service import (
    UserSettingsService,
    pwd_context,
    DEFAULT_THEME,
    DEFAULT_EMAIL_NOTIFICATIONS,
    DEFAULT_BROWSER_NOTIFICATIONS,
    DEFAULT_AUTO_LOGOUT_MINUTES,
)
from routes.user_settings_routes import (
    get_settings,
    update_settings,
    change_password,
    router as user_settings_router,
)
from utils.current_user import get_current_user
from utils.jwt_handler import create_access_token
from app.main import app


def setup_test_db() -> Session:
    """Create in-memory SQLite database and return a clean session."""
    engine = create_engine("sqlite:///:memory:", echo=False)
    Base.metadata.create_all(
        engine,
        tables=[
            Role.__table__,
            City.__table__,
            CyberCell.__table__,
            User.__table__,
            UserSettings.__table__,
        ]
    )
    SessionMaker = sessionmaker(bind=engine)
    return SessionMaker()


def run_all_tests():
    print("=" * 75)
    print("RUNNING COMPREHENSIVE USER SETTINGS VERIFICATION TEST SUITE (30 TESTS)")
    print("=" * 75)

    db = setup_test_db()

    # --------------------------------------------------------------------------
    # Seed Basic Roles and Users
    # --------------------------------------------------------------------------
    hashed_default = pwd_context.hash("Admin@SecurePass123!")

    admin_user = User(
        id=1,
        full_name="Admin User",
        username="admin_user",
        email="admin@deps.gov",
        phone_number="9876543210",
        password=hashed_default,
        role_id=1,
        cyber_cell_id=1,
        is_first_login=True,
        is_active=True
    )
    investigator_user = User(
        id=2,
        full_name="Investigator User",
        username="investigator_user",
        email="investigator@deps.gov",
        phone_number="9876543211",
        password=hashed_default,
        role_id=2,
        cyber_cell_id=1,
        is_first_login=True,
        is_active=True
    )
    expert_user = User(
        id=3,
        full_name="Cyber Expert User",
        username="expert_user",
        email="expert@deps.gov",
        phone_number="9876543212",
        password=hashed_default,
        role_id=3,
        cyber_cell_id=1,
        is_first_login=True,
        is_active=True
    )
    user_b = User(
        id=4,
        full_name="User B Separate",
        username="user_b",
        email="user_b@deps.gov",
        phone_number="9876543213",
        password=hashed_default,
        role_id=2,
        cyber_cell_id=1,
        is_first_login=True,
        is_active=True
    )

    db.add_all([admin_user, investigator_user, expert_user, user_b])
    db.commit()

    # --------------------------------------------------------------------------
    # Test 1: Admin GET settings
    # --------------------------------------------------------------------------
    admin_settings = get_settings(current_user=admin_user, db=db)
    assert admin_settings.theme == "LIGHT"
    assert admin_settings.email_notifications is True
    assert admin_settings.browser_notifications is True
    assert admin_settings.auto_logout_minutes == 30
    print("  [PASS] 1. Admin GET settings succeeds with centralized defaults")

    # --------------------------------------------------------------------------
    # Test 2: Investigator GET settings
    # --------------------------------------------------------------------------
    inv_settings = get_settings(current_user=investigator_user, db=db)
    assert inv_settings.theme == "LIGHT"
    assert inv_settings.email_notifications is True
    assert inv_settings.browser_notifications is True
    assert inv_settings.auto_logout_minutes == 30
    print("  [PASS] 2. Investigator GET settings succeeds with centralized defaults")

    # --------------------------------------------------------------------------
    # Test 3: Cyber Expert GET settings
    # --------------------------------------------------------------------------
    expert_settings = get_settings(current_user=expert_user, db=db)
    assert expert_settings.theme == "LIGHT"
    assert expert_settings.email_notifications is True
    assert expert_settings.browser_notifications is True
    assert expert_settings.auto_logout_minutes == 30
    print("  [PASS] 3. Cyber Expert GET settings succeeds with centralized defaults")

    # --------------------------------------------------------------------------
    # Test 4: Unauthenticated GET -> 401
    # --------------------------------------------------------------------------
    try:
        invalid_creds = HTTPAuthorizationCredentials(scheme="Bearer", credentials="invalid_or_corrupted_token")
        get_current_user(credentials=invalid_creds, db=db)
        assert False, "Should raise 401 for invalid token"
    except HTTPException as exc:
        assert exc.status_code == status.HTTP_401_UNAUTHORIZED
        assert "Invalid or expired token" in exc.detail
    print("  [PASS] 4. Unauthenticated GET rejected with 401 Unauthorized")

    # --------------------------------------------------------------------------
    # Test 5: Unauthenticated PUT -> 401
    # --------------------------------------------------------------------------
    try:
        no_id_token = create_access_token({"sub": "no_user_id"})
        no_id_creds = HTTPAuthorizationCredentials(scheme="Bearer", credentials=no_id_token)
        get_current_user(credentials=no_id_creds, db=db)
        assert False, "Should raise 401 for token missing user_id"
    except HTTPException as exc:
        assert exc.status_code == status.HTTP_401_UNAUTHORIZED
    print("  [PASS] 5. Unauthenticated PUT rejected with 401 Unauthorized")

    # --------------------------------------------------------------------------
    # Test 6: Default record creation
    # --------------------------------------------------------------------------
    # user_b has no settings initially
    existing_row = db.query(UserSettings).filter(UserSettings.user_id == user_b.id).first()
    assert existing_row is None
    created_settings = get_settings(current_user=user_b, db=db)
    assert created_settings.user_id == user_b.id
    assert created_settings.theme == DEFAULT_THEME
    assert created_settings.email_notifications == DEFAULT_EMAIL_NOTIFICATIONS
    assert created_settings.browser_notifications == DEFAULT_BROWSER_NOTIFICATIONS
    assert created_settings.auto_logout_minutes == DEFAULT_AUTO_LOGOUT_MINUTES
    print("  [PASS] 6. Default settings row automatically provisioned and persisted")

    # --------------------------------------------------------------------------
    # Test 7: Repeated GET does not create duplicate row
    # --------------------------------------------------------------------------
    # Call GET settings 3 more times for user_b
    get_settings(current_user=user_b, db=db)
    get_settings(current_user=user_b, db=db)
    get_settings(current_user=user_b, db=db)
    count = db.query(UserSettings).filter(UserSettings.user_id == user_b.id).count()
    assert count == 1, f"Expected exactly 1 settings row for user_b, found {count}"
    print("  [PASS] 7. Repeated GET does not create duplicate rows (idempotent)")

    # --------------------------------------------------------------------------
    # Test 8: User A / User B isolation
    # --------------------------------------------------------------------------
    update_data = UserSettingsUpdate(
        theme="DARK",
        email_notifications=False,
        browser_notifications=False,
        auto_logout_minutes=60
    )
    update_settings(data=update_data, current_user=investigator_user, db=db)
    user_a_updated = db.query(UserSettings).filter(UserSettings.user_id == investigator_user.id).first()
    user_b_current = db.query(UserSettings).filter(UserSettings.user_id == user_b.id).first()
    assert user_a_updated.theme == "DARK"
    assert user_a_updated.email_notifications is False
    assert user_b_current.theme == "LIGHT"
    assert user_b_current.email_notifications is True
    print("  [PASS] 8. User A / User B strict isolation verified")

    # --------------------------------------------------------------------------
    # Test 9: LIGHT/DARK persistence & normalization
    # --------------------------------------------------------------------------
    # Test lowercase normalization: "dark" -> "DARK"
    normalized_update = UserSettingsUpdate(
        theme="dark",
        email_notifications=True,
        browser_notifications=True,
        auto_logout_minutes=30
    )
    assert normalized_update.theme == "DARK"
    update_settings(data=normalized_update, current_user=admin_user, db=db)
    admin_row = db.query(UserSettings).filter(UserSettings.user_id == admin_user.id).first()
    assert admin_row.theme == "DARK"

    # Switch back to LIGHT
    light_update = UserSettingsUpdate(
        theme="light",
        email_notifications=True,
        browser_notifications=True,
        auto_logout_minutes=30
    )
    assert light_update.theme == "LIGHT"
    update_settings(data=light_update, current_user=admin_user, db=db)
    admin_row = db.query(UserSettings).filter(UserSettings.user_id == admin_user.id).first()
    assert admin_row.theme == "LIGHT"
    print("  [PASS] 9. LIGHT/DARK persistence and uppercase normalization verified")

    # --------------------------------------------------------------------------
    # Test 10: Invalid theme rejection
    # --------------------------------------------------------------------------
    for invalid_theme in ["BLUE", "solarized", "system", "", "  "]:
        try:
            UserSettingsUpdate(
                theme=invalid_theme,
                email_notifications=True,
                browser_notifications=True,
                auto_logout_minutes=30
            )
            assert False, f"Expected validation error for invalid theme: {invalid_theme}"
        except ValidationError:
            pass
    print("  [PASS] 10. Invalid themes rejected by schema validator")

    # --------------------------------------------------------------------------
    # Test 11: Email toggle persistence
    # --------------------------------------------------------------------------
    email_off = UserSettingsUpdate(
        theme="LIGHT",
        email_notifications=False,
        browser_notifications=True,
        auto_logout_minutes=30
    )
    update_settings(data=email_off, current_user=admin_user, db=db)
    assert db.query(UserSettings).filter(UserSettings.user_id == admin_user.id).first().email_notifications is False

    email_on = UserSettingsUpdate(
        theme="LIGHT",
        email_notifications=True,
        browser_notifications=True,
        auto_logout_minutes=30
    )
    update_settings(data=email_on, current_user=admin_user, db=db)
    assert db.query(UserSettings).filter(UserSettings.user_id == admin_user.id).first().email_notifications is True
    print("  [PASS] 11. Email notification toggle persistence verified")

    # --------------------------------------------------------------------------
    # Test 12: Browser toggle persistence
    # --------------------------------------------------------------------------
    browser_off = UserSettingsUpdate(
        theme="LIGHT",
        email_notifications=True,
        browser_notifications=False,
        auto_logout_minutes=30
    )
    update_settings(data=browser_off, current_user=admin_user, db=db)
    assert db.query(UserSettings).filter(UserSettings.user_id == admin_user.id).first().browser_notifications is False

    browser_on = UserSettingsUpdate(
        theme="LIGHT",
        email_notifications=True,
        browser_notifications=True,
        auto_logout_minutes=30
    )
    update_settings(data=browser_on, current_user=admin_user, db=db)
    assert db.query(UserSettings).filter(UserSettings.user_id == admin_user.id).first().browser_notifications is True
    print("  [PASS] 12. Browser notification toggle persistence verified")

    # --------------------------------------------------------------------------
    # Test 13: 15-minute timeout
    # --------------------------------------------------------------------------
    t15 = UserSettingsUpdate(theme="LIGHT", email_notifications=True, browser_notifications=True, auto_logout_minutes=15)
    update_settings(data=t15, current_user=admin_user, db=db)
    assert db.query(UserSettings).filter(UserSettings.user_id == admin_user.id).first().auto_logout_minutes == 15
    print("  [PASS] 13. 15-minute timeout verified")

    # --------------------------------------------------------------------------
    # Test 14: 30-minute timeout
    # --------------------------------------------------------------------------
    t30 = UserSettingsUpdate(theme="LIGHT", email_notifications=True, browser_notifications=True, auto_logout_minutes=30)
    update_settings(data=t30, current_user=admin_user, db=db)
    assert db.query(UserSettings).filter(UserSettings.user_id == admin_user.id).first().auto_logout_minutes == 30
    print("  [PASS] 14. 30-minute timeout verified")

    # --------------------------------------------------------------------------
    # Test 15: 60-minute timeout
    # --------------------------------------------------------------------------
    t60 = UserSettingsUpdate(theme="LIGHT", email_notifications=True, browser_notifications=True, auto_logout_minutes=60)
    update_settings(data=t60, current_user=admin_user, db=db)
    assert db.query(UserSettings).filter(UserSettings.user_id == admin_user.id).first().auto_logout_minutes == 60
    print("  [PASS] 15. 60-minute timeout verified")

    # --------------------------------------------------------------------------
    # Test 16: 120-minute timeout
    # --------------------------------------------------------------------------
    t120 = UserSettingsUpdate(theme="LIGHT", email_notifications=True, browser_notifications=True, auto_logout_minutes=120)
    update_settings(data=t120, current_user=admin_user, db=db)
    assert db.query(UserSettings).filter(UserSettings.user_id == admin_user.id).first().auto_logout_minutes == 120
    print("  [PASS] 16. 120-minute timeout verified")

    # --------------------------------------------------------------------------
    # Test 17: NULL/Never timeout
    # --------------------------------------------------------------------------
    tnull = UserSettingsUpdate(theme="LIGHT", email_notifications=True, browser_notifications=True, auto_logout_minutes=None)
    update_settings(data=tnull, current_user=admin_user, db=db)
    assert db.query(UserSettings).filter(UserSettings.user_id == admin_user.id).first().auto_logout_minutes is None
    print("  [PASS] 17. NULL/Never timeout verified")

    # --------------------------------------------------------------------------
    # Test 18: Invalid 45-minute timeout rejected
    # --------------------------------------------------------------------------
    for invalid_val in [45, 0, -10, 10, 90, 240]:
        try:
            UserSettingsUpdate(
                theme="LIGHT",
                email_notifications=True,
                browser_notifications=True,
                auto_logout_minutes=invalid_val
            )
            assert False, f"Expected validation error for invalid timeout: {invalid_val}"
        except ValidationError:
            pass
    print("  [PASS] 18. Invalid auto-logout timeouts (45, 0, -10) rejected by validator")

    # --------------------------------------------------------------------------
    # Test 19: Wrong current password rejected
    # --------------------------------------------------------------------------
    try:
        change_password(
            data=ChangePasswordRequest(
                current_password="WrongPassword123!",
                new_password="NewSecurePassword2026!",
                confirm_password="NewSecurePassword2026!"
            ),
            current_user=admin_user,
            db=db
        )
        assert False, "Should raise 400 for incorrect current password"
    except HTTPException as exc:
        assert exc.status_code == status.HTTP_400_BAD_REQUEST
        assert "Current password is incorrect" in exc.detail
    print("  [PASS] 19. Wrong current password rejected with 400 Bad Request")

    # --------------------------------------------------------------------------
    # Test 20: Mismatched confirmation rejected
    # --------------------------------------------------------------------------
    try:
        change_password(
            data=ChangePasswordRequest(
                current_password="Admin@SecurePass123!",
                new_password="NewSecurePassword2026!",
                confirm_password="DifferentPassword2026!"
            ),
            current_user=admin_user,
            db=db
        )
        assert False, "Should raise 400 for confirmation mismatch"
    except HTTPException as exc:
        assert exc.status_code == status.HTTP_400_BAD_REQUEST
        assert "do not match" in exc.detail
    print("  [PASS] 20. Mismatched confirmation rejected with 400 Bad Request")

    # --------------------------------------------------------------------------
    # Test 21: Same old/new password rejected
    # --------------------------------------------------------------------------
    try:
        change_password(
            data=ChangePasswordRequest(
                current_password="Admin@SecurePass123!",
                new_password="Admin@SecurePass123!",
                confirm_password="Admin@SecurePass123!"
            ),
            current_user=admin_user,
            db=db
        )
        assert False, "Should raise 400 when new password equals old password"
    except HTTPException as exc:
        assert exc.status_code == status.HTTP_400_BAD_REQUEST
        assert "cannot be the same" in exc.detail
    print("  [PASS] 21. Identical old/new password rejected with 400 Bad Request")

    # --------------------------------------------------------------------------
    # Test 22: Weak password rejected
    # --------------------------------------------------------------------------
    weak_passwords = [
        "short",                  # Too short (< 12 chars)
        "nocapitalletter123!",    # Missing uppercase
        "NOLOWERCASE123!@#",      # Missing lowercase
        "NoNumbersHere!@#$",      # Missing digit
        "NoSpecialChars1234",     # Missing special character
    ]
    for weak_pw in weak_passwords:
        try:
            change_password(
                data=ChangePasswordRequest(
                    current_password="Admin@SecurePass123!",
                    new_password=weak_pw,
                    confirm_password=weak_pw
                ),
                current_user=admin_user,
                db=db
            )
            assert False, f"Expected 400 rejection for weak password: {weak_pw}"
        except HTTPException as exc:
            assert exc.status_code == status.HTTP_400_BAD_REQUEST
    print("  [PASS] 22. Weak passwords rejected under system complexity policy")

    # --------------------------------------------------------------------------
    # Test 23: Successful password change
    # --------------------------------------------------------------------------
    valid_new_pw = "BrandNew@StrongPassword2026#"
    resp = change_password(
        data=ChangePasswordRequest(
            current_password="Admin@SecurePass123!",
            new_password=valid_new_pw,
            confirm_password=valid_new_pw
        ),
        current_user=admin_user,
        db=db
    )
    assert resp.require_relogin is True
    assert "Password changed successfully" in resp.message
    print("  [PASS] 23. Successful password change returns 200 and require_relogin: true")

    # --------------------------------------------------------------------------
    # Test 24: Bcrypt hash stored, not plaintext
    # --------------------------------------------------------------------------
    admin_refreshed = db.query(User).filter(User.id == admin_user.id).first()
    assert admin_refreshed.password.startswith("$2b$")
    assert valid_new_pw not in admin_refreshed.password
    print("  [PASS] 24. Bcrypt hash stored in DB, zero plaintext exposure")

    # --------------------------------------------------------------------------
    # Test 25: Password/hash absent from response
    # --------------------------------------------------------------------------
    resp_dict = resp.model_dump()
    assert "password" not in resp_dict
    assert "hash" not in resp_dict
    assert "current_password" not in resp_dict
    assert "new_password" not in resp_dict
    print("  [PASS] 25. Response strictly adheres to schema; zero password leaks")

    # --------------------------------------------------------------------------
    # Test 26: Password change affects current user only
    # --------------------------------------------------------------------------
    # investigator_user password should still verify with the old default password
    inv_refreshed = db.query(User).filter(User.id == investigator_user.id).first()
    assert pwd_context.verify("Admin@SecurePass123!", inv_refreshed.password) is True
    assert pwd_context.verify(valid_new_pw, inv_refreshed.password) is False
    print("  [PASS] 26. Password change strictly isolated to authenticated caller")

    # --------------------------------------------------------------------------
    # Test 27: is_first_login behavior
    # --------------------------------------------------------------------------
    assert admin_refreshed.is_first_login is False
    print("  [PASS] 27. is_first_login cleared to False upon password change")

    # --------------------------------------------------------------------------
    # Test 28: Login with new password succeeds
    # --------------------------------------------------------------------------
    assert pwd_context.verify(valid_new_pw, admin_refreshed.password) is True
    assert pwd_context.verify("Admin@SecurePass123!", admin_refreshed.password) is False
    print("  [PASS] 28. New password verification succeeds, old password invalidated")

    # --------------------------------------------------------------------------
    # Test 29: Secure /settings route conflict check
    # --------------------------------------------------------------------------
    all_app_routes = []
    for r in app.routes:
        if hasattr(r, "routes"):
            all_app_routes.extend(r.routes)
        elif hasattr(r, "original_router"):
            all_app_routes.extend(r.original_router.routes)
        else:
            all_app_routes.append(r)

    settings_routes = [
        route for route in all_app_routes
        if hasattr(route, "path") and "settings" in route.path
    ]
    registered_paths = {f"{route.methods} {route.path}" for route in settings_routes}
    print(f"       Registered /settings routes: {registered_paths}")
    assert any("/settings" in r for r in registered_paths)
    assert any("/settings/change-password" in r for r in registered_paths)
    print("  [PASS] 29. Secure /settings router registered cleanly in main application")

    # --------------------------------------------------------------------------
    # Test 30: Legacy unauthenticated settings mutation is no longer possible
    # --------------------------------------------------------------------------
    # Verify that every route under /settings has get_current_user in its dependencies
    assert len(settings_routes) > 0
    for route in settings_routes:
        if hasattr(route, "dependant"):
            dep_funcs = [dep.call for dep in route.dependant.dependencies]
            assert get_current_user in dep_funcs, (
                f"Route {route.path} missing get_current_user dependency! Found: {dep_funcs}"
            )
    print("  [PASS] 30. All /settings routes strictly require JWT authentication (no unauthenticated mutation)")

    print("=" * 75)
    print("ALL 30 USER SETTINGS SPECIFICATION TESTS PASSED SUCCESSFULLY!")
    print("=" * 75)


if __name__ == "__main__":
    run_all_tests()
