# ============================================================
# 这个文件是干什么的：互动动作的业务逻辑车间——收藏/想试/创意反馈/线索订阅的幂等增删，
#   以及全产品主信号"想看怎么做"的记录与需求路由（§5.1：平台原创通知作者、外部汇入需求看板）。
# 它对应产品里的什么功能：详情页和实现线索页上的全部互动按钮。
# 如果它出错了，用户会看到什么现象：按钮点了没反应或重复计数；最严重的是主信号丢失
#   或游客被错误要求登录（违反红线）。
# ============================================================
import uuid
from datetime import datetime, timedelta, timezone
from typing import Optional, Type

from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.errors import AppError
from app.models import HowToInterest, Notification, Project, ProjectReaction, User


def get_published_project(db: Session, project_id: uuid.UUID) -> Project:
    """互动只允许发生在已发布的项目上；其余状态一律 404（不暴露存在性）。"""
    p = db.get(Project, project_id)
    if p is None or p.deleted_at is not None or p.status != "published":
        raise AppError(404, "NOT_FOUND", "项目不存在")
    return p


# ---------- 收藏 / 想试 / 线索订阅（结构相同：user+project 唯一） ----------


def add_user_link(db: Session, model: Type, user: User, project_id: uuid.UUID) -> None:
    """幂等新增：已存在则什么都不做（重复收藏不报 409，契约约定）。
    并发下两个请求同时通过 exists 检查也安全：唯一约束兜底，撞约束的那个 rollback 当幂等成功。"""
    get_published_project(db, project_id)
    exists = db.scalar(select(model.id).where(model.user_id == user.id, model.project_id == project_id).limit(1))
    if exists:
        return
    db.add(model(user_id=user.id, project_id=project_id))
    try:
        db.commit()
    except IntegrityError:
        db.rollback()  # 并发下另一请求已插入，幂等视为成功，不抛 500


def remove_user_link(db: Session, model: Type, user: User, project_id: uuid.UUID) -> None:
    """幂等删除：不存在也返回成功（204），客户端重试不报错。"""
    row = db.scalar(select(model).where(model.user_id == user.id, model.project_id == project_id).limit(1))
    if row is not None:
        db.delete(row)
        db.commit()


# ---------- 创意反馈（user+project+type 唯一，可取消 toggle） ----------


def add_reaction(db: Session, user: User, project_id: uuid.UUID, reaction_type: str) -> None:
    get_published_project(db, project_id)
    exists = db.scalar(
        select(ProjectReaction.id)
        .where(
            ProjectReaction.user_id == user.id,
            ProjectReaction.project_id == project_id,
            ProjectReaction.reaction_type == reaction_type,
        )
        .limit(1)
    )
    if exists:
        return
    db.add(ProjectReaction(user_id=user.id, project_id=project_id, reaction_type=reaction_type))
    try:
        db.commit()
    except IntegrityError:
        db.rollback()  # 并发下另一请求已插入同类反应，幂等成功


def remove_reaction(db: Session, user: User, project_id: uuid.UUID, reaction_type: str) -> None:
    row = db.scalar(
        select(ProjectReaction)
        .where(
            ProjectReaction.user_id == user.id,
            ProjectReaction.project_id == project_id,
            ProjectReaction.reaction_type == reaction_type,
        )
        .limit(1)
    )
    if row is not None:
        db.delete(row)
        db.commit()


# ---------- 想看怎么做（主信号，§5.1） ----------


def how_to_interest_count(db: Session, project_id: uuid.UUID) -> int:
    return db.scalar(
        select(func.count()).select_from(HowToInterest).where(HowToInterest.project_id == project_id)
    ) or 0


def add_how_to_interest(
    db: Session, project_id: uuid.UUID, user: Optional[User], anon_client_id: Optional[str]
) -> int:
    """记录主信号并返回最新累计数。红线：游客绝不设登录墙——无 token 时用 anon_client_id 去重。
    重复点按幂等成功（返回当前计数，不报错）。"""
    project = get_published_project(db, project_id)

    if not project.allow_how_to_interest:
        raise AppError(409, "HOW_TO_DISABLED", "该项目已关闭「想看怎么做」")
    if user is None and not anon_client_id:
        raise AppError(422, "ANON_ID_REQUIRED", "游客触发想看怎么做必须携带 anon_client_id")

    # 去重：登录用户按 user_id，游客按 anon_client_id（与部分唯一索引一致）
    if user is not None:
        cond = (HowToInterest.user_id == user.id,)
    else:
        cond = (HowToInterest.user_id.is_(None), HowToInterest.anon_client_id == anon_client_id)
    exists = db.scalar(select(HowToInterest.id).where(HowToInterest.project_id == project_id, *cond).limit(1))

    if exists:
        return how_to_interest_count(db, project_id)

    db.add(
        HowToInterest(
            user_id=user.id if user else None,
            anon_client_id=None if user else anon_client_id,
            project_id=project_id,
        )
    )
    try:
        db.flush()  # INSERT 在此触发；并发撞部分唯一索引会在这里抛
    except IntegrityError:
        db.rollback()  # 并发下另一请求已记同一需求，幂等成功，返回当前累计数
        return how_to_interest_count(db, project_id)
    count = how_to_interest_count(db, project_id)
    _route_demand(db, project, user, count)
    db.commit()
    return count


def _route_demand(db: Session, project: Project, actor: Optional[User], count: int) -> None:
    """需求路由（§5.1）：平台用户原创 → 作者站内通知（展示实际累计数，同项目每日最多 1 条聚合更新）；
    外部内容（ai_crawled/manual_import/user_discovery）→ 自然汇入需求看板（聚合查询，无需额外写表）。"""
    if not (project.author_user_id and project.is_original):
        return
    if actor is not None and actor.id == project.author_user_id:
        return  # 作者点自己的项目不通知自己

    title = "有人想看你怎么做"
    body = f"《{project.title}》已累计 {count} 人想看怎么做"
    today_start = datetime.now(timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0)
    existing = db.scalar(
        select(Notification)
        .where(
            Notification.user_id == project.author_user_id,
            Notification.type == "how_to_interest",
            Notification.project_id == project.id,
            Notification.created_at >= today_start,
        )
        .limit(1)
    )
    if existing is not None:
        # 每日聚合：更新累计数并恢复未读（新需求理应再次提醒，但一天只占一条）
        existing.body = body
        existing.is_read = False
        existing.read_at = None
    else:
        db.add(
            Notification(
                user_id=project.author_user_id,
                type="how_to_interest",
                title=title,
                body=body,
                project_id=project.id,
            )
        )


# ---------- 工具：近 N 天窗口 ----------


def window_start(days: int) -> datetime:
    return datetime.now(timezone.utc) - timedelta(days=days)
