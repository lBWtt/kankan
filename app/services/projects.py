# ============================================================
# 这个文件是干什么的：项目查询的组装车间——把数据库里的项目行变成接口要的卡片/详情
#   （含媒体、标签、各类计数、当前用户的收藏/想试状态），以及发现流的筛选+游标翻页。
# 它对应产品里的什么功能：发现页信息流、搜索、看我这行筛选、今日精选、项目详情页。
# 如果它出错了，用户会看到什么现象：信息流刷不出来、详情页计数错乱、翻页重复跳条。
# ============================================================
import uuid
from datetime import datetime
from typing import List, Optional, Tuple

from sqlalchemy import func, or_, select, tuple_
from sqlalchemy.orm import Session

from app.core.errors import AppError
from app.core.pagination import decode_cursor, encode_cursor
from app.models import (
    ClueSubscription,
    Favorite,
    HowToInterest,
    Project,
    ProjectAction,
    ProjectActionEvent,
    ProjectMedia,
    ProjectReaction,
    ProjectTag,
    ProjectTagRelation,
    Share,
    SimilarProjectLink,
    TryItem,
    User,
)
from app.schemas.project import (
    MediaItem,
    ProjectActionOut,
    ProjectCard,
    ProjectCounts,
    ProjectDetail,
    ReactionCounts,
    ViewerState,
)
from app.schemas.user import UserBrief


def card_from_project(p: Project) -> ProjectCard:
    return ProjectCard(
        id=p.id,
        title=p.title,
        tagline=p.tagline,
        subtitle=p.tagline,
        intro=p.intro or p.description or p.summary,
        vertical=p.vertical,
        flag=p.ai_badge if p.ai_badge != "none" else None,
        takeaway_count=p.takeaway_count or 0,
        repo_stars=p.repo_stars,
        cover_media_url=p.cover_media_url,
        category=p.category,
        domains=p.domains or [],
        tools=p.tools or [],
        ai_badge=p.ai_badge,
        published_at=p.published_at,
    )


def list_published(
    db: Session,
    q: Optional[str],
    domain: Optional[str],
    category: Optional[str],
    section: Optional[str],
    cursor: Optional[str],
    page_size: int,
    page: Optional[int],
) -> Tuple[List[Project], Optional[str], bool]:
    """发现流查询：只取 published 且未软删；返回 (本页项目, next_cursor, has_more)。"""
    stmt = select(Project).where(Project.status == "published", Project.deleted_at.is_(None))

    if q:
        like = f"%{q}%"
        # MVP 搜索：标题/亮点模糊 + 工具精确命中（GIN）；中文分词升级是后续项
        stmt = stmt.where(or_(Project.title.ilike(like), Project.tagline.ilike(like), Project.tools.any(q)))
    if domain:
        stmt = stmt.where(Project.domains.any(domain))
    if category:
        stmt = stmt.where(Project.category == category)

    if section == "today_pick":
        # 今日精选：运营设置 featured_rank，量小，不分页
        rows = db.scalars(
            stmt.where(Project.featured_rank.isnot(None)).order_by(Project.featured_rank.asc())
        ).all()
        return rows, None, False

    stmt = stmt.order_by(Project.published_at.desc(), Project.id.desc())
    if cursor:
        dt_s, id_s = decode_cursor(cursor, 2)
        try:
            c_dt = datetime.fromisoformat(dt_s)
            c_id = uuid.UUID(id_s)
        except ValueError:
            raise AppError(422, "VALIDATION_FAILED", "cursor 无效")
        stmt = stmt.where(tuple_(Project.published_at, Project.id) < (c_dt, c_id))
    elif page and page > 1:
        # 兼容 page 参数（契约 §1）；优先 cursor
        stmt = stmt.offset((page - 1) * page_size)

    rows = db.scalars(stmt.limit(page_size + 1)).all()
    has_more = len(rows) > page_size
    rows = rows[:page_size]
    next_cursor = None
    if has_more and rows:
        last = rows[-1]
        next_cursor = encode_cursor([last.published_at.isoformat(), str(last.id)])
    return rows, next_cursor, has_more


def similar_published(db: Session, project_id: uuid.UUID) -> List[Project]:
    """「类似作品」：similar_project_links 里 source=当前项目 且 B 已发布的，按关联时间倒序（§5.2）。"""
    return list(
        db.scalars(
            select(Project)
            .join(SimilarProjectLink, SimilarProjectLink.similar_project_id == Project.id)
            .where(
                SimilarProjectLink.source_project_id == project_id,
                Project.status == "published",
                Project.deleted_at.is_(None),
            )
            .order_by(SimilarProjectLink.created_at.desc())
        )
    )


def clue_related_projects(db: Session, p: Project, limit: int = 6) -> List[Project]:
    """线索页的关联推荐（§4.11"类似作品/推荐项目"）：先放已发布的类似作品，
    不足再用同分类已发布项目按热度补位（补全决策：文档未定补位规则，取最朴素可解释的）。"""
    related = similar_published(db, p.id)[:limit]
    if len(related) < limit:
        exclude = {p.id} | {r.id for r in related}
        fill = db.scalars(
            select(Project)
            .where(
                Project.status == "published",
                Project.deleted_at.is_(None),
                Project.category == p.category,
                Project.id.notin_(exclude),
            )
            .order_by(Project.hot_score.desc(), Project.published_at.desc())
            .limit(limit - len(related))
        ).all()
        related = related + list(fill)
    return related


def list_linked_projects(
    db: Session, link_model, user: User, cursor: Optional[str], page_size: int
) -> Tuple[List[Project], Optional[str], bool]:
    """我的收藏/想试列表：按动作时间倒序，游标=（动作时间,动作行id）；
    只展示仍是 published 的项目（被下架/删除的自动隐藏，不报错）。"""
    stmt = (
        select(link_model, Project)
        .join(Project, Project.id == link_model.project_id)
        .where(
            link_model.user_id == user.id,
            Project.status == "published",
            Project.deleted_at.is_(None),
        )
        .order_by(link_model.created_at.desc(), link_model.id.desc())
    )
    if cursor:
        dt_s, id_s = decode_cursor(cursor, 2)
        try:
            c_dt = datetime.fromisoformat(dt_s)
            c_id = uuid.UUID(id_s)
        except ValueError:
            raise AppError(422, "VALIDATION_FAILED", "cursor 无效")
        stmt = stmt.where(tuple_(link_model.created_at, link_model.id) < (c_dt, c_id))

    rows = db.execute(stmt.limit(page_size + 1)).all()
    has_more = len(rows) > page_size
    rows = rows[:page_size]
    next_cursor = None
    if has_more and rows:
        last_link = rows[-1][0]
        next_cursor = encode_cursor([last_link.created_at.isoformat(), str(last_link.id)])
    return [proj for _, proj in rows], next_cursor, has_more


def get_visible_project(db: Session, project_id: uuid.UUID, user: Optional[User]) -> Project:
    """详情可见性：published 人人可见；其他状态仅作者本人/管理员，否则一律 404（不暴露存在性）。"""
    p = db.get(Project, project_id)
    if p is None or p.deleted_at is not None:
        raise AppError(404, "NOT_FOUND", "项目不存在")
    if p.status != "published":
        is_owner = user is not None and p.author_user_id == user.id
        is_admin = user is not None and user.is_admin
        if not (is_owner or is_admin):
            raise AppError(404, "NOT_FOUND", "项目不存在")
    return p


def counts_for_project(db: Session, pid: uuid.UUID) -> ProjectCounts:
    """五类互动计数（详情页与分享卡共用）。"""
    def cnt(model) -> int:
        return db.scalar(select(func.count()).select_from(model).where(model.project_id == pid)) or 0

    reaction_rows = db.execute(
        select(ProjectReaction.reaction_type, func.count())
        .where(ProjectReaction.project_id == pid)
        .group_by(ProjectReaction.reaction_type)
    ).all()
    reactions = ReactionCounts(**{rt: n for rt, n in reaction_rows})
    shares_completed = db.scalar(
        select(func.count()).select_from(Share).where(Share.project_id == pid, Share.share_status == "completed")
    ) or 0
    action_clicks = db.scalar(
        select(func.count()).select_from(ProjectActionEvent).where(
            ProjectActionEvent.project_id == pid,
            ProjectActionEvent.event_type == "click",
        )
    ) or 0
    takeaway_count = db.scalar(select(Project.takeaway_count).where(Project.id == pid)) or 0
    return ProjectCounts(
        favorites=cnt(Favorite),
        tries=cnt(TryItem),
        how_to_interests=cnt(HowToInterest),
        shares_completed=shares_completed,
        action_clicks=action_clicks,
        takeaways=takeaway_count,
        reactions=reactions,
    )


def _viewer_state(db: Session, pid: uuid.UUID, user: Optional[User]) -> ViewerState:
    if user is None:
        return ViewerState()

    def has(model) -> bool:
        return bool(db.scalar(select(model.id).where(model.project_id == pid, model.user_id == user.id).limit(1)))

    my_reactions = db.scalars(
        select(ProjectReaction.reaction_type).where(
            ProjectReaction.project_id == pid, ProjectReaction.user_id == user.id
        )
    ).all()
    return ViewerState(
        is_favorited=has(Favorite),
        is_tried=has(TryItem),
        has_how_to_interest=has(HowToInterest),
        is_clue_subscribed=has(ClueSubscription),
        reactions=list(my_reactions),
    )


def detail_from_project(db: Session, p: Project, user: Optional[User]) -> ProjectDetail:
    media = db.scalars(
        select(ProjectMedia).where(ProjectMedia.project_id == p.id).order_by(ProjectMedia.sort_order.asc())
    ).all()
    actions = db.scalars(
        select(ProjectAction).where(ProjectAction.project_id == p.id).order_by(
            ProjectAction.sort_order.asc(),
            ProjectAction.created_at.asc(),
        )
    ).all()
    tags = db.scalars(
        select(ProjectTag.name)
        .join(ProjectTagRelation, ProjectTagRelation.tag_id == ProjectTag.id)
        .where(ProjectTagRelation.project_id == p.id)
    ).all()
    author = None
    if p.author_user_id:
        u = db.get(User, p.author_user_id)
        if u is not None:
            author = UserBrief(id=u.id, nickname=u.nickname, avatar_url=u.avatar_url, role=u.role)
    other_projects = []
    if p.author_user_id is not None:
        other_projects = db.scalars(
            select(Project)
            .where(
                Project.status == "published",
                Project.deleted_at.is_(None),
                Project.id != p.id,
                Project.author_user_id == p.author_user_id,
            )
            .order_by(Project.published_at.desc())
            .limit(6)
        ).all()

    card = card_from_project(p).model_dump()
    for field in ("author", "counts", "viewer"):
        card.pop(field, None)

    return ProjectDetail(
        **card,
        summary=p.summary,
        description=p.description,
        language=p.language,
        source_type=p.source_type,
        is_original=p.is_original,
        source_url=p.source_url,
        source_platform=p.source_platform,
        original_author_name=p.original_author_name,
        original_author_url=p.original_author_url,
        media=[
            MediaItem(
                id=m.id, media_type=m.media_type, kind=m.media_type,
                url=m.url, thumbnail_url=m.thumbnail_url, sort_order=m.sort_order
            )
            for m in media
        ],
        actions=[
            ProjectActionOut(
                id=a.id,
                action_type=a.action_type,
                action_sub=a.action_sub,
                label=a.label,
                sublabel=a.sublabel,
                content=a.content,
                file_media_id=a.file_media_id,
                file_name=a.file_name,
                file_size_bytes=a.file_size_bytes,
                url=a.url,
                sort_order=a.sort_order,
            )
            for a in actions
        ],
        tags=list(tags),
        ai_implementation_hint=p.ai_implementation_hint,
        target_users=p.target_users or [],
        use_cases=p.use_cases or [],
        allow_how_to_interest=p.allow_how_to_interest,
        status=p.status,
        author=author,
        counts=counts_for_project(db, p.id),
        viewer=_viewer_state(db, p.id, user),
        related_projects=[card_from_project(x) for x in clue_related_projects(db, p, limit=6)],
        other_projects=[card_from_project(x) for x in other_projects],
        created_at=p.created_at,
    )
