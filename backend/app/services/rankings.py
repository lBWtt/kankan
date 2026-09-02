# ============================================================
# 这个文件是干什么的：榜单的计算车间——按 §5.4 公式算行为热度分
#   hot_score = Σ(行为×权重) × 0.5^(age_hours/72)，本周热门用近 7 天行为，结果缓存进 Redis。
# 它对应产品里的什么功能：榜单 Tab 的本周热门/最新/今日精选三类。
# 如果它出错了，用户会看到什么现象：榜单页空白、排序明显不对，或每次打开都很慢。
# ============================================================
import json
import secrets
import time
import uuid
from typing import Dict, List, Optional, Tuple

from sqlalchemy import extract, func, literal, select, union_all
from sqlalchemy.orm import Session

from app.core.redis import redis_client
from app.models import AnalyticsEvent, Favorite, HowToInterest, Project, ProjectAction, ProjectActionEvent, Share, TryItem
from app.services.interactions import window_start

# 行为权重（PRD §10 / 字段 v1.3 §5.4）。「想试」是主信号，权重 5（列名仍是 how_to_interest）。
# view/detail_click 来自埋点表（补全决策：view=card_impression、detail_click=detail_view，
# 事件名对齐字段 v1.3 §10 清单）；其余从互动子表聚合。
_W_VIEW, _W_DETAIL = 1.0, 2.0
_W_FAVORITE, _W_TRY, _W_WANT_TRY, _W_SHARE = 4.0, 4.0, 5.0, 6.0
_W_ACTION_TAKE_SUCCESS, _W_ACTION_HOW_CLICK, _W_ACTION_GO_CLICK = 6.0, 5.0, 3.0

_HALF_LIFE_HOURS = 72.0  # 时间衰减 0.5^(age_hours/72)，约 3 天半衰期
_CACHE_KEY = "rankings:weekly_hot"
_CACHE_TTL_SECONDS = 3600  # PRD：每小时刷新；MVP 用"过期后下个请求重算"实现
_LOCK_KEY = "rankings:lock"  # 分布式锁防止并发重算
_LOCK_TTL_SECONDS = 120  # 调大到 120 秒，覆盖最慢重算（防止锁过期后被别人接管产生并发重算）


def _decay_factor(created_at_col):
    """单条行为的衰减系数：0.5^(距今小时数/72)。"""
    age_hours = extract("epoch", func.now() - created_at_col) / 3600.0
    return func.power(0.5, age_hours / _HALF_LIFE_HOURS)


def compute_weekly_hot(db: Session, limit: Optional[int]) -> List[Tuple[uuid.UUID, float]]:
    """按近 7 天行为算 hot_score，返回 [(project_id, score)] 降序；limit=None 取全部有行为的项目。
    每条行为按自身年龄单独衰减后求和（公式按行为粒度应用，避免老项目新热度被整体抹平）。"""
    since = window_start(7)

    def _source(model, weight: float, *extra_where):
        return (
            select(
                model.project_id.label("pid"),
                (literal(weight) * _decay_factor(model.created_at)).label("score"),
            )
            .where(model.created_at >= since, *extra_where)
        )

    sources = [
        _source(Favorite, _W_FAVORITE),
        _source(TryItem, _W_TRY),
        _source(HowToInterest, _W_WANT_TRY),
        _source(Share, _W_SHARE, Share.share_status == "completed"),
        _source(AnalyticsEvent, _W_VIEW, AnalyticsEvent.event_name == "card_impression",
                AnalyticsEvent.project_id.isnot(None)),
        _source(AnalyticsEvent, _W_DETAIL, AnalyticsEvent.event_name == "detail_view",
                AnalyticsEvent.project_id.isnot(None)),
        select(
            ProjectActionEvent.project_id.label("pid"),
            (literal(_W_ACTION_TAKE_SUCCESS) * _decay_factor(ProjectActionEvent.created_at)).label("score"),
        )
        .join(ProjectAction, ProjectAction.id == ProjectActionEvent.action_id)
        .where(
            ProjectActionEvent.created_at >= since,
            ProjectActionEvent.event_type == "success",
            ProjectAction.action_type == "take",
        ),
        select(
            ProjectActionEvent.project_id.label("pid"),
            (literal(_W_ACTION_HOW_CLICK) * _decay_factor(ProjectActionEvent.created_at)).label("score"),
        )
        .join(ProjectAction, ProjectAction.id == ProjectActionEvent.action_id)
        .where(
            ProjectActionEvent.created_at >= since,
            ProjectActionEvent.event_type == "click",
            ProjectAction.action_type == "how",
        ),
        select(
            ProjectActionEvent.project_id.label("pid"),
            (literal(_W_ACTION_GO_CLICK) * _decay_factor(ProjectActionEvent.created_at)).label("score"),
        )
        .join(ProjectAction, ProjectAction.id == ProjectActionEvent.action_id)
        .where(
            ProjectActionEvent.created_at >= since,
            ProjectActionEvent.event_type == "click",
            ProjectAction.action_type == "go",
        ),
    ]
    behaviors = union_all(*sources).subquery()

    stmt = (
        select(behaviors.c.pid, func.sum(behaviors.c.score).label("total"))
        .join(Project, Project.id == behaviors.c.pid)
        .where(Project.status == "published", Project.deleted_at.is_(None))
        .group_by(behaviors.c.pid)
        .order_by(func.sum(behaviors.c.score).desc())
    )
    if limit is not None:
        stmt = stmt.limit(limit)
    return [(pid, float(total)) for pid, total in db.execute(stmt).all()]


def _store_cache(scored: List[Tuple[uuid.UUID, float]]) -> None:
    """榜单写进 Redis（1 小时有效）；Redis 不可用就算了，下个请求现算（榜单变慢但不挂）。"""
    try:
        redis_client.set(
            _CACHE_KEY, json.dumps([str(pid) for pid, _ in scored[:100]]), ex=_CACHE_TTL_SECONDS
        )
    except Exception:
        pass


def refresh_weekly_hot(db: Session) -> List[Tuple[uuid.UUID, float]]:
    """重算本周热门并把分数回写 projects.hot_score（后台列表和补位排序也用它）+ 刷新缓存。
    每小时定时任务和缓存过期后的首个请求都走这里。"""
    scored = compute_weekly_hot(db, limit=100)
    score_map: Dict[uuid.UUID, float] = dict(scored)
    if score_map:
        for p in db.scalars(select(Project).where(Project.id.in_(score_map.keys()))):
            p.hot_score = score_map[p.id]
        db.commit()
    _store_cache(scored)
    return scored


def calibrate_hot_scores(db: Session) -> int:
    """每日 00:10 全量校准（PRD §7.2）：所有已发布项目重算 hot_score——
    增量刷新只更新上榜的，行为衰减到 0 的老项目要靠这次归零。返回更新条数。"""
    score_map = dict(compute_weekly_hot(db, limit=None))
    updated = 0
    for p in db.scalars(select(Project).where(Project.status == "published", Project.deleted_at.is_(None))):
        new_score = score_map.get(p.id, 0.0)
        if p.hot_score != new_score:
            p.hot_score = new_score
            updated += 1
    db.commit()
    _store_cache(sorted(score_map.items(), key=lambda kv: kv[1], reverse=True))
    return updated


def _read_cache() -> Optional[List[uuid.UUID]]:
    """读榜单缓存：Redis 不可用、内容损坏（坏 JSON / 非 UUID）都当未命中（返回 None），
    让上层重算——绝不让脏缓存把 /rankings 打成 500。损坏的键顺手删掉，免得后续请求一直踩。"""
    try:
        cached = redis_client.get(_CACHE_KEY)
    except Exception:
        return None
    if not cached:
        return None
    try:
        return [uuid.UUID(s) for s in json.loads(cached)]
    except (ValueError, TypeError, json.JSONDecodeError):
        try:
            redis_client.delete(_CACHE_KEY)
        except Exception:
            pass
        return None


def weekly_hot_ids(db: Session, limit: int) -> List[uuid.UUID]:
    """本周热门：先读 Redis 缓存，过期/不足/损坏则重算。
    使用分布式锁防止并发重算：首个请求获取锁后重算，其他请求等待或返回旧缓存。

    安全释放（H-SVC-2）：锁值为随机 token，释放时用 Lua 脚本原子比对 token 后才删。
    避免锁过期后持有者已释放、另一进程抢到锁后本进程译误删除，导致三进程同时重算。
    """
    ranked = _read_cache()
    if ranked is not None and len(ranked) >= limit:
        return ranked[:limit]
    
    # 尝试获取分布式锁（token 随机，释放时用它安全比对），防止并发重算
    token = secrets.token_hex(8)
    lock_acquired = False
    try:
        # SETNX: 只有键不存在时才设置成功；值为 token，释放时比对它
        lock_acquired = redis_client.set(_LOCK_KEY, token, nx=True, ex=_LOCK_TTL_SECONDS)
    except Exception:
        pass  # Redis 不可用时跳过锁，继续重算
    
    if not lock_acquired:
        # 其他请求正在重算，短暂等待后再次读取缓存
        time.sleep(0.5)  # sync 端点跑在线程池，不阻塞事件循环
        ranked = _read_cache()
        if ranked is not None and len(ranked) >= limit:
            return ranked[:limit]
        # 等待后仍无缓存，自己重算（牺牲一点性能不牺牲正确性）
        scored = compute_weekly_hot(db, limit=limit)
        return [pid for pid, _ in scored]
    
    try:
        scored = refresh_weekly_hot(db)
        return [pid for pid, _ in scored[:limit]]
    finally:
        # 安全释放：Lua 脚本原子 GET+DEL，只有 token 一致才删（锁已过期被别人接管则不删）
        try:
            redis_client.eval(
                'if redis.call("get", KEYS[1]) == ARGV[1] then return redis.call("del", KEYS[1]) else return 0 end',
                1, _LOCK_KEY, token
            )
        except Exception:
            pass


def fetch_in_order(db: Session, ids: List[uuid.UUID]) -> List[Project]:
    """按给定 ID 顺序取项目（榜单顺序由计算结果决定，不靠 SQL 排序）。
    必须过滤 status=published 且未软删：榜单缓存最长存活 1 小时，期间若有项目被
    下架/删除，不过滤就会把不可见内容继续挂在榜单上展示给用户。"""
    if not ids:
        return []
    rows = {
        p.id: p
        for p in db.scalars(
            select(Project).where(
                Project.id.in_(ids),
                Project.status == "published",
                Project.deleted_at.is_(None),
            )
        )
    }
    return [rows[i] for i in ids if i in rows]


# ---------- 动态榜 / 作者榜（阶段3补：原来只有项目榜，动态/作者走 mock）----------

def hot_posts(db: Session, limit: int = 50):
    """动态榜：按点赞数（like_count 去规范化）降序，时间新的优先。返回 Post 行列表。"""
    from app.models import Post
    return list(db.scalars(
        select(Post).order_by(Post.like_count.desc(), Post.created_at.desc()).limit(limit)
    ).all())


def top_authors(db: Session, limit: int = 50) -> List[dict]:
    """作者榜：每位作者的总获赞（已发布项目的反应数 + 动态 like_count 之和）+ 项目数 + 动态数，
    按总获赞降序取前 N。返回 dict 列表（供 AuthorRankOut 组装）。"""
    from app.models import Post, ProjectReaction, User

    proj_rows = db.execute(
        select(Project.author_user_id, Project.id).where(
            Project.status == "published",
            Project.deleted_at.is_(None),
            Project.author_user_id.isnot(None),
        )
    ).all()
    react_rows = db.execute(
        select(ProjectReaction.project_id, func.count()).group_by(ProjectReaction.project_id)
    ).all()
    react_by_proj = {pid: n for pid, n in react_rows}
    post_rows = db.execute(select(Post.author_user_id, Post.like_count)).all()

    acc: dict = {}

    def slot(aid):
        return acc.setdefault(aid, {"likes": 0, "projects": 0, "posts": 0})

    for aid, pid in proj_rows:
        s = slot(aid)
        s["projects"] += 1
        s["likes"] += react_by_proj.get(pid, 0)
    for aid, lc in post_rows:
        s = slot(aid)
        s["posts"] += 1
        s["likes"] += (lc or 0)

    ranked = sorted(acc.items(), key=lambda kv: kv[1]["likes"], reverse=True)[:limit]
    author_ids = [aid for aid, _ in ranked]
    users = (
        {u.id: u for u in db.scalars(select(User).where(User.id.in_(author_ids)))}
        if author_ids else {}
    )
    out: List[dict] = []
    for aid, s in ranked:
        u = users.get(aid)
        if u is None or u.deleted_at is not None:
            continue
        out.append({
            "user_id": aid,
            "nickname": u.nickname,
            "avatar_url": u.avatar_url,
            "total_likes": s["likes"],
            "project_count": s["projects"],
            "post_count": s["posts"],
        })
    return out
