from sqlalchemy.orm import Session

from models.notification import Notification


# ==========================================
# Create Notification
# ==========================================

def create_notification(
    db: Session,
    title: str,
    message: str,
    notification_type: str
):

    notification = Notification(

        title=title,

        message=message,

        type=notification_type,

        is_read=False

    )

    db.add(notification)

    db.commit()

    db.refresh(notification)

    return notification


# ==========================================
# Get All Notifications
# ==========================================

def get_notifications(db: Session):

    return (
        db.query(Notification)
        .order_by(Notification.created_at.desc())
        .all()
    )


# ==========================================
# Unread Notification Count
# ==========================================

def get_unread_count(db: Session):

    count = (
        db.query(Notification)
        .filter(Notification.is_read == False)
        .count()
    )

    return {"count": count}


# ==========================================
# Mark Notification Read
# ==========================================

def mark_notification_read(
    db: Session,
    notification_id: int
):

    notification = (
        db.query(Notification)
        .filter(Notification.id == notification_id)
        .first()
    )

    if notification is None:
        return None

    notification.is_read = True

    db.commit()

    db.refresh(notification)

    return notification