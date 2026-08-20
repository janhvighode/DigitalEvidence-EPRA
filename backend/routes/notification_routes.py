from typing import List

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from database.database import get_db
from models.user import User
from utils.current_user import get_current_user

from services.notification_service import (
    get_notifications,
    get_unread_count,
    mark_notification_read
)

from schemas.notification import (
    NotificationResponse,
    NotificationCountResponse
)

router = APIRouter(
    prefix="/notifications",
    tags=["Notifications"]
)


# ==========================================
# Get Notifications
# ==========================================

@router.get(
    "/",
    response_model=List[NotificationResponse]
)
def fetch_notifications(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):

    return get_notifications(
        db,
        current_user
    )


# ==========================================
# Get Unread Count
# ==========================================

@router.get(
    "/unread-count",
    response_model=NotificationCountResponse
)
def unread_notifications(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):

    return get_unread_count(
        db,
        current_user
    )


# ==========================================
# Mark Notification Read
# ==========================================

@router.put("/{notification_id}/read")
def read_notification(
    notification_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):

    notification = mark_notification_read(
        db,
        notification_id,
        current_user
    )

    if notification is None:
        raise HTTPException(
            status_code=404,
            detail="Notification not found"
        )

    return {
        "message": "Notification marked as read."
    }