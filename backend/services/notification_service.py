from typing import Optional, Dict, Any, List
from fastapi import HTTPException, status
from sqlalchemy.orm import Session
from models.notification import Notification
from models.user import User


# ==========================================
# Create Notification
# ==========================================

def create_notification(
    db: Session,
    title: str,
    message: str,
    notification_type: str = "GENERAL",
    user_id: Optional[int] = None,
    cyber_cell_id: Optional[int] = None,
    case_id: Optional[str] = None,
    evidence_id: Optional[str] = None
) -> Optional[Notification]:
    """
    Creates a user-specific notification with practical deduplication.
    Enforces that notifications belong strictly to a designated user_id.
    Prevents accidental recipient-less / orphan notifications in new code.
    """
    if not user_id:
        # Prevent orphan notifications with null recipient
        return None

    # Practical Deduplication:
    # If an identical unread notification already exists for this recipient, return it
    existing = (
        db.query(Notification)
        .filter(
            Notification.user_id == user_id,
            Notification.type == notification_type,
            Notification.title == title,
            Notification.message == message,
            Notification.is_read == False
        )
        .first()
    )
    if existing:
        return existing

    notification = Notification(
        title=title.strip(),
        message=message.strip(),
        type=notification_type.strip(),
        user_id=user_id,
        cyber_cell_id=None,  # Scoping is strictly per-user; no branch broadcast leakage
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
    current_user: User,
    page: int = 1,
    limit: int = 20
) -> Dict[str, Any]:
    """
    Retrieves paginated notifications strictly scoped to the authenticated user.
    Rule: Notification.user_id == current_user.id for ALL roles.
    Zero cross-user leakage or historical branch broadcast leakage.
    """
    if page < 1:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Page number must be greater than or equal to 1"
        )
    if limit < 1 or limit > 100:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Limit must be between 1 and 100"
        )

    base_query = db.query(Notification).filter(
        Notification.user_id == current_user.id
    )

    total = base_query.count()
    unread_count = base_query.filter(Notification.is_read == False).count()

    offset = (page - 1) * limit
    items = (
        base_query
        .order_by(
            Notification.created_at.desc(),
            Notification.id.desc()
        )
        .offset(offset)
        .limit(limit)
        .all()
    )

    return {
        "page": page,
        "limit": limit,
        "total": total,
        "unread_count": unread_count,
        "items": items
    }


# ==========================================
# Unread Count
# ==========================================

def get_unread_count(
    db: Session,
    current_user: User
) -> Dict[str, int]:
    """
    Returns unread notification count strictly for current_user.id.
    """
    count = db.query(Notification).filter(
        Notification.user_id == current_user.id,
        Notification.is_read == False
    ).count()

    return {
        "count": count
    }


# ==========================================
# Mark Notification Read
# ==========================================

def mark_notification_read(
    db: Session,
    notification_id: int,
    current_user: User
) -> Optional[Notification]:
    """
    Marks a single notification as read.
    Enforces strict ownership: Notification.id == notification_id AND Notification.user_id == current_user.id.
    Unauthorized / other-user notification returns None.
    """
    notification = db.query(Notification).filter(
        Notification.id == notification_id,
        Notification.user_id == current_user.id
    ).first()

    if notification is None:
        return None

    notification.is_read = True
    db.commit()
    db.refresh(notification)

    return notification


# ==========================================
# Mark All Read
# ==========================================

def mark_all_read(
    db: Session,
    current_user: User
) -> int:
    """
    Marks all unread notifications for current_user.id as read.
    Affects ONLY the authenticated user's records.
    """
    updated_count = (
        db.query(Notification)
        .filter(
            Notification.user_id == current_user.id,
            Notification.is_read == False
        )
        .update({"is_read": True}, synchronize_session=False)
    )

    db.commit()
    return updated_count