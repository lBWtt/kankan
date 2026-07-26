# ============================================================
# 这个文件是干什么的：话题接口路由——热门话题列表 + 单个话题详情。
# 它对应产品里的什么功能：话题广场 / 今日话题横条（列表）、话题详情页（详情）。
# 话题是对 projects.tools + posts.tags 的实时聚合（见 services/topics.py），游客可用。
# ============================================================
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from app.api.deps import ERRORS_AUTHED, ERRORS_PUBLIC, auth_optional, auth_required
from app.core.db import get_db
from app.models import User
from app.schemas.topic import TopicDetail, TopicOut
from app.schemas.common import OkResponse
from app.services import topics as svc

router = APIRouter(prefix="/topics", tags=["话题"], responses=ERRORS_PUBLIC)


@router.get("", response_model=List[TopicOut], summary="热门话题（聚合 tools+tags，游客可用）")
def list_topics(
    limit: int = Query(30, ge=1, le=100, description="返回前 N 个高热话题"),
    db: Session = Depends(get_db),
    viewer: Optional[User] = Depends(auth_optional),
):
    return svc.aggregate_topics(db, limit=limit, viewer=viewer)


@router.get("/followed", response_model=List[TopicOut], responses=ERRORS_AUTHED)
def list_followed_topics(
    user: User = Depends(auth_required), db: Session = Depends(get_db)
):
    return svc.followed_topics(db, user)


def _validate_tag(tag: str) -> str:
    try:
        return svc.normalize_tag(tag)
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc


@router.post("/{tag}/follow", response_model=OkResponse, status_code=201, responses=ERRORS_AUTHED)
def follow_topic(
    tag: str, user: User = Depends(auth_required), db: Session = Depends(get_db)
):
    svc.follow_topic(db, user, _validate_tag(tag))
    return OkResponse()


@router.delete("/{tag}/follow", status_code=204, responses=ERRORS_AUTHED)
def unfollow_topic(
    tag: str, user: User = Depends(auth_required), db: Session = Depends(get_db)
):
    svc.unfollow_topic(db, user, _validate_tag(tag))


@router.get("/{tag}", response_model=TopicDetail, summary="话题详情：该 tag 下的项目+动态（游客可用）")
def get_topic(
    tag: str,
    viewer: Optional[User] = Depends(auth_optional),
    db: Session = Depends(get_db),
):
    return svc.topic_detail(db, tag, viewer)
