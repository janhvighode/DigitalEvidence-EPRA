from typing import List

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from database.database import get_db

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
# Get All Notifications
# ==========================================

@router.get(
    "/",
    response_model=List[NotificationResponse]
)
def fetch_notifications(
    db: Session = Depends(get_db)
):
    return get_notifications(db)


# ==========================================
# Get Unread Count
# ==========================================

@router.get(
    "/unread-count",
    response_model=NotificationCountResponse
)
def unread_notifications(
    db: Session = Depends(get_db)
):
    return get_unread_count(db)


# ==========================================
# Mark Notification Read
# ==========================================

@router.put("/{notification_id}/read")
def read_notification(
    notification_id: int,
    db: Session = Depends(get_db)
):

    notification = mark_notification_read(
        db,
        notification_id
    )

    if notification is None:
        raise HTTPException(
            status_code=404,
            detail="Notification not found"
        )

    return {
        "message": "Notification marked as read."
    }