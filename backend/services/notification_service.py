from sqlalchemy.orm import Session
from sqlalchemy import or_
from models.notification import Notification


# ==========================================
# Create Notification
# ==========================================

def create_notification(
    db: Session,
    title: str,
    message: str,
    notification_type: str,
    user_id: int = None,
    cyber_cell_id: int = None
):

    notification = Notification(
        title=title,
        message=message,
        type=notification_type,
        user_id=user_id,
        cyber_cell_id=cyber_cell_id,
        is_read=False
    )

    db.add(notification)
    db.commit()
    db.refresh(notification)

    return notification


# ==========================================
# Get Notifications For Logged-in User
# ==========================================

def get_notifications(
    db: Session,
    current_user
):

    # Administrator
    if current_user.role_id == 1:
        return (
          db.query(Notification)
        .filter(
            or_(
                Notification.cyber_cell_id ==
                current_user.cyber_cell_id,

                Notification.user_id ==
                current_user.id
            )
        )
        .order_by(Notification.created_at.desc())
        .all()
    )

    # Investigator / Cyber Expert
    return (
        db.query(Notification)
        .filter(
            Notification.user_id == current_user.id
        )
        .order_by(Notification.created_at.desc())
        .all()
    )


# ==========================================
# Unread Count
# ==========================================

def get_unread_count(
    db: Session,
    current_user
):

    query = db.query(Notification).filter(
        Notification.is_read == False
    )

    # Administrator
    if current_user.role_id == 1:

        query = query.filter(
            or_(
                Notification.cyber_cell_id == current_user.cyber_cell_id,
                Notification.user_id == current_user.id
            )
        )

    # Investigator / Cyber Expert
    else:

        query = query.filter(
            Notification.user_id == current_user.id
        )

    return {
        "count": query.count()
    }

# ==========================================
# Mark Notification Read
# ==========================================

def mark_notification_read(
    db: Session,
    notification_id: int,
    current_user
):

    query = db.query(Notification).filter(
        Notification.id == notification_id
    )

    # Administrator
    if current_user.role_id == 1:

        query = query.filter(
            or_(
                Notification.cyber_cell_id == current_user.cyber_cell_id,
                Notification.user_id == current_user.id
            )
        )

    # Investigator / Cyber Expert
    else:

        query = query.filter(
            Notification.user_id == current_user.id
        )

    notification = query.first()

    if notification is None:
        return None

    notification.is_read = True

    db.commit()
    db.refresh(notification)

    return notification