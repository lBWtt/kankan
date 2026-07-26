# ============================================================
# 这个文件是干什么的：话题聚合车间——把 projects.tools + posts.tags 实时算成「话题」列表/详情。
# 它对应产品里的什么功能：话题广场、今日话题横条、话题详情页。
# 如果它出错了：话题广场空/热度错、话题页刷不出该 tag 下的内容。
# 口径与前端 search_repository 一致：heat = 项目数*10 + 动态数*5 + 总赞//100（真实聚合，不放大）。
# ============================================================
from typing import List, Optional

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.models import Post, PostLike, Project, ProjectReaction, TopicFollow, User
from app.schemas.topic import TopicDetail, TopicOut
from app.services.posts import _posts_to_out
from app.services.projects import cards_from_projects_with_stats


def _heat(project_count: int, post_count: int, total_likes: int) -> int:
    return project_count * 10 + post_count * 5 + total_likes // 100


def aggregate_topics(
    db: Session, limit: int = 30, viewer: Optional[User] = None
) -> List[TopicOut]:
    """扫全量已发布项目(tools) + 全量动态(tags)，聚合每个 tag 的项目数/动态数/总赞/热度。
    4 条批量查询，Python 里做累加（当前数据量足够；规模化后可物化）。"""
    # 项目：id + tools（tag 来源）
    proj_rows = db.execute(
        select(Project.id, Project.tools).where(
            Project.status == "published", Project.deleted_at.is_(None)
        )
    ).all()
    # 每个项目的反应总数（= 前端「点赞」口径：三种反应之和 = count(*)）
    react_rows = db.execute(
        select(ProjectReaction.project_id, func.count()).group_by(ProjectReaction.project_id)
    ).all()
    react_by_proj = {pid: n for pid, n in react_rows}
    # 动态：id + tags + like_count（去规范化的赞数）
    post_rows = db.execute(select(Post.id, Post.tags, Post.like_count)).all()

    acc: dict[str, dict] = {}

    def slot(tag: str) -> dict:
        return acc.setdefault(tag, {"project_count": 0, "post_count": 0, "total_likes": 0})

    for pid, tools in proj_rows:
        likes = react_by_proj.get(pid, 0)
        for tag in (tools or []):
            s = slot(tag)
            s["project_count"] += 1
            s["total_likes"] += likes
    for _pid, tags, like_count in post_rows:
        for tag in (tags or []):
            s = slot(tag)
            s["post_count"] += 1
            s["total_likes"] += (like_count or 0)

    topics = [
        TopicOut(
            tag=tag,
            project_count=s["project_count"],
            post_count=s["post_count"],
            total_likes=s["total_likes"],
            heat=_heat(s["project_count"], s["post_count"], s["total_likes"]),
        )
        for tag, s in acc.items()
    ]
    if viewer is not None:
        followed = set(db.scalars(
            select(TopicFollow.tag).where(TopicFollow.user_id == viewer.id)
        ).all())
        topics = [t.model_copy(update={"is_followed": t.tag in followed}) for t in topics]
    topics.sort(key=lambda t: t.heat, reverse=True)
    return topics[:limit] if limit else topics


def normalize_tag(tag: str) -> str:
    value = tag.strip().lstrip("#").strip()
    if not value or len(value) > 64:
        raise ValueError("Topic tag must contain 1 to 64 characters")
    return value


def follow_topic(db: Session, user: User, tag: str) -> None:
    tag = normalize_tag(tag)
    exists = db.scalar(select(TopicFollow).where(
        TopicFollow.user_id == user.id, TopicFollow.tag == tag
    ))
    if exists is None:
        db.add(TopicFollow(user_id=user.id, tag=tag))
        db.commit()


def unfollow_topic(db: Session, user: User, tag: str) -> None:
    tag = normalize_tag(tag)
    row = db.scalar(select(TopicFollow).where(
        TopicFollow.user_id == user.id, TopicFollow.tag == tag
    ))
    if row is not None:
        db.delete(row)
        db.commit()


def followed_topics(db: Session, user: User) -> List[TopicOut]:
    follows = list(db.scalars(
        select(TopicFollow)
        .where(TopicFollow.user_id == user.id)
        .order_by(TopicFollow.created_at.desc())
    ).all())
    aggregate = {topic.tag: topic for topic in aggregate_topics(db, limit=0)}
    return [
        aggregate.get(f.tag, TopicOut(
            tag=f.tag, heat=0, project_count=0, post_count=0,
            total_likes=0,
        )).model_copy(update={"is_followed": True})
        for f in follows
    ]


def topic_detail(db: Session, tag: str, viewer: Optional[User] = None) -> TopicDetail:
    """某个 tag 下的项目（tools 精确命中，GIN 索引）+ 动态（tags 精确命中），按热度/时间排。"""
    projects = list(db.scalars(
        select(Project).where(
            Project.status == "published",
            Project.deleted_at.is_(None),
            Project.tools.any(tag),
        ).order_by(Project.published_at.desc())
    ).all())
    posts = list(db.scalars(
        select(Post).where(Post.tags.any(tag)).order_by(Post.created_at.desc())
    ).all())

    proj_cards = cards_from_projects_with_stats(db, projects)
    post_outs = _posts_to_out(db, posts, viewer)

    # total_likes 与聚合口径一致：项目反应总数之和 + 动态 like_count 之和
    def _card_likes(c) -> int:
        r = c.counts.reactions if c.counts else None
        return (r.creative + r.big_brain + r.cool) if r else 0

    total_likes = sum(_card_likes(c) for c in proj_cards) + sum(p.likes for p in post_outs)
    is_followed = viewer is not None and db.scalar(select(TopicFollow.id).where(
        TopicFollow.user_id == viewer.id, TopicFollow.tag == tag
    )) is not None
    topic = TopicOut(
        tag=tag,
        project_count=len(proj_cards),
        post_count=len(post_outs),
        total_likes=total_likes,
        heat=_heat(len(proj_cards), len(post_outs), total_likes),
        is_followed=is_followed,
    )
    return TopicDetail(topic=topic, projects=proj_cards, posts=post_outs)
