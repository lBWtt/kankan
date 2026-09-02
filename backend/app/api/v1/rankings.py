# ============================================================
# 这个文件是干什么的：榜单接口的路由——本周热门 / 最新 / 今日精选三类（MVP）。
# 它对应产品里的什么功能：榜单 Tab；本周热门用近 7 天 hot_score（Redis 缓存 1 小时刷新）。
# 如果它出错了，用户会看到什么现象：榜单页空白或排序明显不对。
# ============================================================
from datetime import datetime, timezone
from enum import Enum
from typing import List, Optional

from fastapi import APIRouter, Depends, Query
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.deps import ERRORS_PUBLIC, auth_optional
from app.core.db import get_db
from app.models import Project, User
from app.schemas.post import PostOut
from app.schemas.project import AuthorRankOut, RankedItem, RankingResponse
from app.services.posts import _posts_to_out
from app.services.projects import cards_from_projects_with_stats
from app.services.rankings import fetch_in_order, hot_posts, top_authors, weekly_hot_ids

router = APIRouter(prefix="/rankings", tags=["榜单"], responses=ERRORS_PUBLIC)


class RankingType(str, Enum):
    weekly_hot = "weekly_hot"   # 近 7 天 hot_score，Redis 缓存每小时过期重算
    latest = "latest"           # published_at 降序，近实时
    today_pick = "today_pick"   # featured_rank 非空按序（运营手动）


@router.get("", response_model=RankingResponse, summary="榜单（游客可用，MVP 三类）")
def get_rankings(
    type: RankingType = Query(RankingType.weekly_hot),
    limit: int = Query(50, ge=1, le=100),
    db: Session = Depends(get_db),
):
    """most_favorited / most_creative 移 V3，不在本契约内。"""
    published = select(Project).where(Project.status == "published", Project.deleted_at.is_(None))

    if type == RankingType.weekly_hot:
        rows = fetch_in_order(db, weekly_hot_ids(db, limit))
    elif type == RankingType.latest:
        rows = db.scalars(
            published.order_by(Project.published_at.desc(), Project.id.desc()).limit(limit)
        ).all()
    else:  # today_pick
        rows = db.scalars(
            published.where(Project.featured_rank.isnot(None)).order_by(Project.featured_rank.asc()).limit(limit)
        ).all()

    # 批量填充 author 和 counts，与发现流/收藏列表一致（榜单卡片也该带互动数据）
    cards = cards_from_projects_with_stats(db, rows)
    return RankingResponse(
        type=type.value,
        generated_at=datetime.now(timezone.utc),
        items=[RankedItem(rank=i + 1, project=c) for i, c in enumerate(cards)],
    )


@router.get("/posts", response_model=List[PostOut], summary="动态榜（按赞降序，游客可用）")
def get_post_rankings(
    limit: int = Query(50, ge=1, le=100),
    viewer: Optional[User] = Depends(auth_optional),
    db: Session = Depends(get_db),
):
    """动态榜：按 like_count 降序。前端按返回顺序取名次。"""
    return _posts_to_out(db, hot_posts(db, limit), viewer)


@router.get("/authors", response_model=List[AuthorRankOut], summary="作者榜（按总获赞降序，游客可用）")
def get_author_rankings(
    limit: int = Query(50, ge=1, le=100),
    db: Session = Depends(get_db),
):
    """作者榜：总获赞 = 已发布项目的反应数 + 动态赞数之和。前端按返回顺序取名次。"""
    return [AuthorRankOut(**a) for a in top_authors(db, limit)]
