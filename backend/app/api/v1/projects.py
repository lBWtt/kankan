# ============================================================
# 这个文件是干什么的：项目主资源的路由——发现流/搜索列表、详情（V0 已实现），
#   发布/编辑/删除、类似作品、实现线索页（V1 已全部实现）。
# 它对应产品里的什么功能：发现页、搜索页、项目详情页、发布页、实现线索页（P0）。
# 如果它出错了，用户会看到什么现象：App 核心内容全部刷不出来。
# ============================================================
import uuid
from typing import Optional

from fastapi import APIRouter, Depends, Query
from sqlalchemy import select
from sqlalchemy.orm import Session
from typing_extensions import Literal

from app.api.deps import ERRORS_AUTHED, ERRORS_PUBLIC, auth_optional, auth_required
from app.core.db import get_db
from app.core.ratelimit import rate_limit
from app.models import User
from app.schemas.common import Category, ContentType, Domain, Page
from app.schemas.project import (
    ImplementationClue,
    HomeSlateResponse,
    ProjectCard,
    ProjectCreate,
    ProjectDetail,
    ProjectUpdate,
    SimilarProjectsResponse,
)
from app.services.interactions import how_to_interest_count
from app.services.publishing import create_user_project, soft_delete_project, update_user_project
from app.services.projects import (
    cards_from_projects_with_stats,
    clue_related_projects,
    detail_from_project,
    get_visible_project,
    list_published,
    similar_published,
)
from app.services.slate import home_slate

router = APIRouter(prefix="/projects", tags=["项目"])


@router.get(
    "/home-slate", response_model=HomeSlateResponse, responses=ERRORS_PUBLIC,
    summary="内容宪法 v1.1 首页首批十条（游客可用）",
)
def get_home_slate(db: Session = Depends(get_db)):
    result = home_slate(db)
    return HomeSlateResponse(
        slate_id=result.slate_id,
        items=cards_from_projects_with_stats(db, result.projects),
        shortages=result.shortages,
    )


@router.get(
    "", response_model=Page[ProjectCard], responses=ERRORS_PUBLIC,
    summary="发现流 / 搜索 / 筛选（游客可用）",
)
def list_projects(
    q: Optional[str] = Query(None, max_length=80, description="搜索 title/tagline/tools"),
    domain: Optional[Domain] = Query(None, description="看我这行筛选"),
    category: Optional[Category] = None,
    content_type: Optional[ContentType] = Query(None, description="内容类型（成果类型）筛选"),
    section: Optional[Literal["today_pick"]] = Query(None, description="today_pick=今日精选（按 featured_rank 排序）"),
    cursor: Optional[str] = None,
    page_size: int = Query(20, ge=1, le=50),
    page: Optional[int] = Query(None, ge=1, description="兼容参数，优先用 cursor"),
    db: Session = Depends(get_db),
):
    """只返回 status=published，按 published_at 降序；today_pick 按 featured_rank 升序不分页。
    （按 interests 个性化加权是 V1 项。）"""
    rows, next_cursor, has_more = list_published(
        db,
        q=q,
        domain=domain.value if domain else None,
        category=category.value if category else None,
        content_type=content_type.value if content_type else None,
        section=section,
        cursor=cursor,
        page_size=page_size,
        page=page,
    )
    # 批量组装：cards_from_projects_with_stats 内部批量自查 author + counts，无需 selectinload
    items = cards_from_projects_with_stats(db, rows)
    return Page[ProjectCard](items=items, next_cursor=next_cursor, has_more=has_more)


@router.post(
    "", response_model=ProjectDetail, status_code=201, responses=ERRORS_AUTHED,
    summary="发布项目（需登录）",
)
def create_project(
    body: ProjectCreate,
    user: User = Depends(auth_required),
    db: Session = Depends(get_db),
):
    """发布准入（PRD §2.3 红线）：tools≥1 或 description 含可复现说明，
    否则 409 PUBLISH_GATE_FAILED（纯单图无方法不予发布）。
    user_original/user_discovery 默认直接发布（status=published）。"""
    # H-API-6: 用户级频控——每分钟最多 5 个项目，防项目刷量
    rate_limit(f"projects:create:{user.id}", limit=5, window=60)
    project = create_user_project(db, user, body)
    db.commit()
    return detail_from_project(db, project, user)


@router.get(
    "/{project_id}", response_model=ProjectDetail, responses=ERRORS_PUBLIC,
    summary="项目详情（游客可用）",
)
def get_project(
    project_id: uuid.UUID,
    user: Optional[User] = Depends(auth_optional),
    db: Session = Depends(get_db),
):
    """非 published 状态：作者本人与管理员可见，其余 404 NOT_FOUND（不暴露存在性）。
    登录用户附带 viewer 状态（是否已收藏/想试/点过想看怎么做）。"""
    project = get_visible_project(db, project_id, user)
    return detail_from_project(db, project, user)


@router.patch(
    "/{project_id}", response_model=ProjectDetail, responses=ERRORS_AUTHED,
    summary="编辑自己的项目（需登录）",
)
def update_project(
    project_id: uuid.UUID,
    body: ProjectUpdate,
    user: User = Depends(auth_required),
    db: Session = Depends(get_db),
):
    """只能改自己的项目，否则 403 FORBIDDEN。轻编辑直接生效；改完仍须满足发布准入。"""
    project = update_user_project(db, user, project_id, body)
    db.commit()
    return detail_from_project(db, project, user)


@router.delete(
    "/{project_id}", status_code=204, responses=ERRORS_AUTHED,
    summary="删除自己的项目（软删，需登录）",
)
def delete_project(
    project_id: uuid.UUID,
    user: User = Depends(auth_required),
    db: Session = Depends(get_db),
):
    """软删：status=deleted + deleted_at，不物理删除（红线：删除与下架是两个状态）。"""
    soft_delete_project(db, user, project_id)
    db.commit()


@router.get(
    "/{project_id}/similar", response_model=SimilarProjectsResponse, responses=ERRORS_PUBLIC,
    summary="类似作品（游客可用）",
)
def similar_projects(
    project_id: uuid.UUID,
    user: Optional[User] = Depends(auth_optional),
    db: Session = Depends(get_db),
):
    """source_project_id=当前项目 且 status=published 的"我做了类似的"作品。"""
    get_visible_project(db, project_id, user)
    similar = similar_published(db, project_id)
    # 使用批量组装函数，填充 author 和 counts（一致性，复用批量函数防 N+1）
    items = cards_from_projects_with_stats(db, similar)
    return SimilarProjectsResponse(items=items)


@router.get(
    "/{project_id}/implementation-clue", response_model=ImplementationClue, responses=ERRORS_PUBLIC,
    summary="实现线索页（P0，游客可用）",
)
def implementation_clue(
    project_id: uuid.UUID,
    user: Optional[User] = Depends(auth_optional),
    db: Session = Depends(get_db),
):
    """来源/工具/AI 思路/关联推荐/当前"想试"数。（"订阅更新"功能已随 clue_subscriptions 删除。）"""
    p = get_visible_project(db, project_id, user)
    return ImplementationClue(
        project_id=p.id,
        source_url=p.source_url,
        source_platform=p.source_platform,
        original_author_name=p.original_author_name,
        original_author_url=p.original_author_url,
        tools=p.tools or [],
        ai_implementation_hint=p.ai_implementation_hint,
        related_projects=cards_from_projects_with_stats(db, clue_related_projects(db, p)),  # 填充 author/counts
        how_to_interest_count=how_to_interest_count(db, p.id),
    )
