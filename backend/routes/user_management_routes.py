from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from database.database import get_db

from services.user_management_service import (
    get_all_users,
    get_user_by_id,
    search_users,
    update_user,
    change_user_status
)

from schemas.user_management import (
    UserResponse,
    UserUpdate,
    UserStatusUpdate
)

router = APIRouter(prefix="/users", tags=["User Management"])


@router.get("/", response_model=list[UserResponse])
def fetch_users(db: Session = Depends(get_db)):
    return get_all_users(db)


@router.get("/search")
def search(keyword: str, db: Session = Depends(get_db)):
    return search_users(db, keyword)


@router.get("/{user_id}", response_model=UserResponse)
def fetch_user(user_id: int, db: Session = Depends(get_db)):
    user = get_user_by_id(db, user_id)

    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    return user


@router.put("/{user_id}", response_model=UserResponse)
def edit_user(user_id: int,
              data: UserUpdate,
              db: Session = Depends(get_db)):

    user = update_user(db, user_id, data)

    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    return user


@router.put("/{user_id}/status")
def update_status(user_id: int,
                  data: UserStatusUpdate,
                  db: Session = Depends(get_db)):

    user = change_user_status(db, user_id, data.is_active)

    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    return user