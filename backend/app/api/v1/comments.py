# ============================================================
# 这个文件是干什么的：评论接口路由——列评论、发评论、删评论、评论点赞。
# 它对应产品里的什么功能：项目/动态详情下的评论区（含一层楼中楼）。
# 如果它出错了，用户会看到什么现象：评论区打不开、发不出、删不掉、赞不动。
# ============================================================
import uuid
from typing import Optional

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.api.deps import ERRORS_AUTHED, ERRORS_PUBLIC, auth_optional, auth_required
from app.core.db import get_db
from app.core.ratelimit import rate_limit
from app.models import User
from app.schemas.comment import CommentCreate, CommentOut
from app.schemas.common import OkResponse, Page
from app.services import comments as svc

router = APIRouter(prefix="/comments", tags=["评论"], responses=ERRORS_PUBLIC)


@router.get("", response_model=Page[CommentOut], summary="评论列表（游客可用，含楼中楼）")
def list_comments(
    host_type: str = Query(..., description="project | post"),
    host_id: uuid.UUID = Query(...),
    cursor: Optional[str] = None,
    page_size: int = Query(20, ge=1, le=50),
    viewer: Optional[User] = Depends(auth_optional),
    db: Session = Depends(get_db),
):
    """顶级评论倒序分页，每条内嵌其楼中楼回复。登录时附带 is_liked。"""
    items, next_cursor, has_more = svc.list_comments(db, host_type, host_id, viewer, cursor, page_size)
    return Page[CommentOut](items=items, next_cursor=next_cursor, has_more=has_more)


@router.post("", response_model=CommentOut, status_code=201, responses=ERRORS_AUTHED,
             summary="发评论（需登录）")
def create_comment(body: CommentCreate, user: User = Depends(auth_required), db: Session = Depends(get_db)):
    """回复顶级评论时带 parent_comment_id；楼中楼仅一层，回复子回复 422。宿主不存在 404。"""
    # H-API-6: 用户级频控——每分钟最多 20 条评论，防评论刷量
    rate_limit(f"comments:create:{user.id}", limit=20, window=60)
    return svc.create_comment(db, user, body.host_type, body.host_id, body.content, body.parent_comment_id)


@router.delete("/{comment_id}", status_code=204, responses=ERRORS_AUTHED, summary="删评论（需登录，仅本人）")
def delete_comment(comment_id: uuid.UUID, user: User = Depends(auth_required), db: Session = Depends(get_db)):
    svc.delete_comment(db, user, comment_id)


@router.post("/{comment_id}/like", response_model=OkResponse, status_code=201, responses=ERRORS_AUTHED,
             summary="给评论点赞（需登录，幂等）")
def like_comment(comment_id: uuid.UUID, user: User = Depends(auth_required), db: Session = Depends(get_db)):
    svc.set_comment_like(db, user, comment_id, True)
    return OkResponse()


@router.delete("/{comment_id}/like", status_code=204, responses=ERRORS_AUTHED,
               summary="取消评论点赞（需登录，幂等）")
def unlike_comment(comment_id: uuid.UUID, user: User = Depends(auth_required), db: Session = Depends(get_db)):
    svc.set_comment_like(db, user, comment_id, False)
