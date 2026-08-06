from sqlalchemy.orm import Session

from models.settings import Settings

# Temporary Administrator ID
ADMIN_ID = 1


def get_settings(db: Session):

    settings = (
        db.query(Settings)
        .filter(Settings.user_id == ADMIN_ID)
        .first()
    )

    # Create default settings if not found
    if settings is None:

        settings = Settings(
            user_id=ADMIN_ID,
            email_notifications=True,
            browser_notifications=True,
            auto_logout=30
        )

        db.add(settings)
        db.commit()
        db.refresh(settings)

    return settings


def update_settings(db: Session, data):

    settings = (
        db.query(Settings)
        .filter(Settings.user_id == ADMIN_ID)
        .first()
    )

    if settings is None:

        settings = Settings(user_id=ADMIN_ID)
        db.add(settings)

    settings.email_notifications = data.email_notifications
    settings.browser_notifications = data.browser_notifications
    settings.auto_logout = data.auto_logout

    db.commit()
    db.refresh(settings)

    return settings