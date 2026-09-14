from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session

from database.database import get_db
from models.user import User
from utils.current_user import get_current_user

from services.notification_service import (
    get_notifications,
    get_unread_count,
    mark_notification_read,
    mark_all_read,
)

from schemas.notification import (
    NotificationResponse,
    NotificationCountResponse,
    NotificationListPage,
    NotificationActionResponse,
)

router = APIRouter(
    prefix="/notifications",
    tags=["Notifications"]
)


# ==========================================
# Get Notifications (Paginated)
# ==========================================

@router.get(
    "",
    response_model=NotificationListPage,
    summary="Get Paginated User Notifications"
)
@router.get(
    "/",
    response_model=NotificationListPage,
    include_in_schema=False
)
def fetch_notifications(
    page: int = Query(1, ge=1, description="Page number"),
    limit: int = Query(20, ge=1, le=100, description="Items per page"),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Returns paginated notifications strictly scoped to current_user.id.
    Chronological descending order (newest first).
    """
    return get_notifications(
        db=db,
        current_user=current_user,
        page=page,
        limit=limit
    )


# ==========================================
# Get Unread Count
# ==========================================

@router.get(
    "/unread-count",
    response_model=NotificationCountResponse,
    summary="Get Unread Notification Count"
)
def unread_notifications(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Returns count of unread notifications strictly belonging to current_user.id.
    """
    return get_unread_count(
        db=db,
        current_user=current_user
    )


# ==========================================
# Mark All Notifications Read
# ==========================================

@router.put(
    "/read-all",
    response_model=NotificationActionResponse,
    summary="Mark All Current User Notifications Read"
)
def read_all_notifications(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Marks all unread notifications for the authenticated user as read.
    """
    updated_count = mark_all_read(
        db=db,
        current_user=current_user
    )
    return NotificationActionResponse(
        message="All unread notifications marked as read.",
        updated_count=updated_count
    )


# ==========================================
# Mark Single Notification Read
# ==========================================

@router.put(
    "/{notification_id}/read",
    response_model=NotificationActionResponse,
    summary="Mark Specific Notification Read"
)
def read_notification(
    notification_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Marks a single notification as read.
    Enforces strict ownership: caller must own the notification (user_id == current_user.id).
    """
    notification = mark_notification_read(
        db=db,
        notification_id=notification_id,
        current_user=current_user
    )

    if notification is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Notification not found"
        )

    return NotificationActionResponse(
        message="Notification marked as read.",
        updated_count=1
    )