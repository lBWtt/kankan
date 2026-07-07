# ============================================================
# 这个文件是干什么的：动态接口路由——动态流、发/看/删动态、动态点赞。
# 它对应产品里的什么功能：发现页动态流、发动态、动态详情、动态点赞。
# 如果它出错了，用户会看到什么现象：动态流打不开、发不出、删不掉、赞不动。
# ============================================================
import uuid
from typing import Optional

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.api.deps import ERRORS_AUTHED, ERRORS_PUBLIC, auth_optional, auth_required
from app.core.db import get_db
from app.models import User
from app.schemas.common import OkResponse, Page
from app.schemas.post import PostCreate, PostOut
from app.services import posts as svc

router = APIRouter(prefix="/posts", tags=["动态"], responses=ERRORS_PUBLIC)


@router.get("", response_model=Page[PostOut], summary="动态流（游客可用）")
def list_posts(
    cursor: Optional[str] = None,
    page_size: int = Query(20, ge=1, le=50),
    viewer: Optional[User] = Depends(auth_optional),
    db: Session = Depends(get_db),
):
    items, next_cursor, has_more = svc.list_posts(db, viewer, cursor, page_size)
    return Page[PostOut](items=items, next_cursor=next_cursor, has_more=has_more)


@router.post("", response_model=PostOut, status_code=201, responses=ERRORS_AUTHED, summary="发动态（需登录）")
def create_post(body: PostCreate, user: User = Depends(auth_required), db: Session = Depends(get_db)):
    return svc.create_post(db, user, body.content, body.tags, body.quote_project_id, body.media_ids)


@router.get("/{post_id}", response_model=PostOut, summary="动态详情（游客可用）")
def get_post(post_id: uuid.UUID, viewer: Optional[User] = Depends(auth_optional), db: Session = Depends(get_db)):
    return svc.get_post(db, post_id, viewer)


@router.delete("/{post_id}", status_code=204, responses=ERRORS_AUTHED, summary="删动态（需登录，仅本人）")
def delete_post(post_id: uuid.UUID, user: User = Depends(auth_required), db: Session = Depends(get_db)):
    svc.delete_post(db, user, post_id)


@router.post("/{post_id}/like", response_model=OkResponse, status_code=201, responses=ERRORS_AUTHED,
             summary="给动态点赞（需登录，幂等）")
def like_post(post_id: uuid.UUID, user: User = Depends(auth_required), db: Session = Depends(get_db)):
    svc.set_post_like(db, user, post_id, True)
    return OkResponse()


@router.delete("/{post_id}/like", status_code=204, responses=ERRORS_AUTHED,
               summary="取消动态点赞（需登录，幂等）")
def unlike_post(post_id: uuid.UUID, user: User = Depends(auth_required), db: Session = Depends(get_db)):
    svc.set_post_like(db, user, post_id, False)
