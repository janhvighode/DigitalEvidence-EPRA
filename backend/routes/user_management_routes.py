from fastapi import APIRouter, Depends, HTTPException
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy.orm import Session

from database.database import get_db
from utils.jwt_handler import verify_access_token

from models.user import User
from utils.current_user import get_current_user

from services.user_management_service import (
    get_all_users,
    get_user_by_id,
    search_users,
    update_user,
    change_user_status,
    get_investigators_by_cyber_cell,
    get_branch_users_for_admin,
    get_cyber_experts_by_cyber_cell
)

from schemas.user_management import (
    UserResponse,
    UserUpdate,
    UserStatusUpdate
)

router = APIRouter(prefix="/users", tags=["User Management"])
security = HTTPBearer()


@router.get("/", response_model=list[UserResponse])
def fetch_users(db: Session = Depends(get_db)):
    return get_all_users(db)


@router.get("/search")
def search(keyword: str, db: Session = Depends(get_db)):
    return search_users(db, keyword)

@router.get(
    "/investigators",
    response_model=list[UserResponse]
)
def fetch_investigators_by_cyber_cell(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):

    if current_user.role_id != 1:
        raise HTTPException(
            status_code=403,
            detail="Administrator access required"
        )

    return get_investigators_by_cyber_cell(
        db,
        current_user.cyber_cell_id
    )
    

@router.get(
    "/branch-users",
    response_model=list[UserResponse]
)
def fetch_branch_users(
    credentials: HTTPAuthorizationCredentials = Depends(security),
    db: Session = Depends(get_db)
):

    payload = verify_access_token(
        credentials.credentials
    )

    if payload is None:
        raise HTTPException(
            status_code=401,
            detail="Invalid or expired token"
        )

    admin_user_id = payload.get("user_id")
    role_id = payload.get("role_id")

    if admin_user_id is None:
        raise HTTPException(
            status_code=401,
            detail="Invalid token"
        )

    if role_id != 1:
        raise HTTPException(
            status_code=403,
            detail="Administrator access required"
        )

    users = get_branch_users_for_admin(
        db,
        admin_user_id
    )

    if users is None:
        raise HTTPException(
            status_code=404,
            detail="Administrator not found"
        )

    return users

@router.get(
    "/cyber-experts",
    response_model=list[UserResponse]
)
def fetch_cyber_experts_by_cyber_cell(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):

    if current_user.role_id != 1:
        raise HTTPException(
            status_code=403,
            detail="Administrator access required"
        )

    return get_cyber_experts_by_cyber_cell(
        db,
        current_user.cyber_cell_id
    )


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