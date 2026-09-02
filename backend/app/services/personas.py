# ============================================================
# 这个文件是干什么的：站内「马甲号」——approve 外部内容时，把作者设成一个马甲账号，
#   让转存进来的内容读起来像真实用户自己发的帖（冷启动做种策略）。
# 它对应产品里的什么功能：审核通过→建项目时随机派一个马甲当作者（决策：不留出处、纯用户原创感）。
# 如果它出错了：没有马甲则作者为空（回退到旧行为，不阻断 approve）。
#
# 马甲用 email 域名 `@persona.kankan` 标识（免加 is_persona 字段/迁移）；由 seed_personas.py 建。
# ============================================================
import random
import uuid
from typing import List, Optional

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.models import Post, Project, User
from app.services.persona_archetypes import ARCHETYPES, archetype_of_email

# 马甲账号的 email 域名标识（seed_personas.py 与此处必须一致）
PERSONA_EMAIL_DOMAIN = "persona.kankan"


def persona_users(db: Session) -> List[User]:
    """取全部马甲号（按 email 域名标识）。"""
    return list(
        db.execute(
            select(User).where(
                User.email.like(f"%@{PERSONA_EMAIL_DOMAIN}"),
                User.deleted_at.is_(None),
            )
        ).scalars()
    )


def is_persona(user: Optional[User]) -> bool:
    """判断一个用户是否马甲号（按 email 域名）。"""
    return bool(user and user.email and user.email.endswith(f"@{PERSONA_EMAIL_DOMAIN}"))


def pick_random_persona(db: Session) -> Optional[User]:
    """随机挑一个马甲当发布者。没有马甲则返回 None（approve 回退为无站内作者）。
    保留作兜底：无内容信息时用它。正常审核发布走 pick_persona_for（按人设匹配+均衡）。"""
    users = persona_users(db)
    return random.choice(users) if users else None


# 马甲的人设偏好现在由「人设原型库」提供（10 套原型，50 个马甲各归一套）。
# 目的：approve 时把内容派给"读起来像会发这个的人"，而不是纯随机张冠李戴。
# 见 app/services/persona_archetypes.py（ARCHETYPES + archetype_of_email）。
def _persona_affinity(u: User) -> dict:
    """取某马甲的兴趣偏好 {cats, domains}——从 email 反推人设原型。"""
    local = (u.email or "").split("@")[0]
    arch = archetype_of_email(local)
    return ARCHETYPES.get(arch, {})


def _persona_live_counts(db: Session, ids: List[uuid.UUID]) -> dict:
    """每个马甲名下未删的项目+动态数——用于负载均衡（发得少的优先派，别偏科）。"""
    counts = {i: 0 for i in ids}
    for uid, n in db.execute(
        select(Project.author_user_id, func.count())
        .where(Project.author_user_id.in_(ids), Project.deleted_at.is_(None))
        .group_by(Project.author_user_id)
    ):
        counts[uid] = counts.get(uid, 0) + n
    for uid, n in db.execute(
        select(Post.author_user_id, func.count())
        .where(Post.author_user_id.in_(ids), Post.deleted_at.is_(None))
        .group_by(Post.author_user_id)
    ):
        counts[uid] = counts.get(uid, 0) + n
    return counts


def pick_persona_for(
    db: Session,
    *,
    category: Optional[str] = None,
    domains: Optional[List[str]] = None,
) -> Optional[User]:
    """审核发布时"合理"地派马甲作者：按人设匹配内容分类/领域（+2 命中分类、+1 命中领域），
    叠加负载均衡（发得少的加成，最多 +1）与轻抖动（打散平局、留一点随机）。取总分最高者。
    没有马甲返回 None；内容无分类/领域时退化为"均衡随机"（仍比纯随机稳）。"""
    users = persona_users(db)
    if not users:
        return None
    ids = [u.id for u in users]
    load = _persona_live_counts(db, ids)
    max_load = max(load.values()) if load else 0
    dset = {d for d in (domains or []) if d}

    best, best_score = None, None
    for u in users:
        aff = _persona_affinity(u)
        score = 0.0
        if category and category in aff.get("cats", set()):
            score += 2.0
        if dset & aff.get("domains", set()):
            score += 1.0
        # 负载均衡：发得少的马甲加成（0~1），50 个号产出别失衡
        score += 1.0 * (1 - load.get(u.id, 0) / (max_load + 1))
        # 抖动：打散平局 + 保留少量随机（不足以盖过分类命中的 +2）
        score += random.uniform(0, 0.6)
        if best_score is None or score > best_score:
            best, best_score = u, score
    return best


def personas_with_stats(db: Session) -> List[dict]:
    """全部马甲 + 各自产出的内容量（未删项目/动态数、动态获赞、最近活跃时间）。
    后台「马甲统一管理」列表用——初期靠马甲撑内容，得一眼看清谁发了多少、反响如何。"""
    personas = persona_users(db)
    if not personas:
        return []
    ids = [p.id for p in personas]

    # 未删项目数（按作者聚合）
    proj_rows = db.execute(
        select(Project.author_user_id, func.count(), func.max(Project.created_at))
        .where(Project.author_user_id.in_(ids), Project.deleted_at.is_(None))
        .group_by(Project.author_user_id)
    ).all()
    proj_cnt = {uid: n for uid, n, _ in proj_rows}
    proj_last = {uid: last for uid, _, last in proj_rows}

    # 未删动态数 + 获赞总数（按作者聚合）
    post_rows = db.execute(
        select(
            Post.author_user_id,
            func.count(),
            func.coalesce(func.sum(Post.like_count), 0),
            func.max(Post.created_at),
        )
        .where(Post.author_user_id.in_(ids), Post.deleted_at.is_(None))
        .group_by(Post.author_user_id)
    ).all()
    post_cnt = {uid: n for uid, n, _, _ in post_rows}
    post_likes = {uid: likes for uid, _, likes, _ in post_rows}
    post_last = {uid: last for uid, _, _, last in post_rows}

    out = []
    for p in personas:
        lasts = [d for d in (proj_last.get(p.id), post_last.get(p.id)) if d is not None]
        out.append({
            "id": p.id,
            "nickname": p.nickname,
            "handle": p.handle,
            "avatar_url": p.avatar_url,
            "bio": p.bio,
            "project_count": proj_cnt.get(p.id, 0),
            "post_count": post_cnt.get(p.id, 0),
            "total_post_likes": int(post_likes.get(p.id, 0)),
            "last_active": max(lasts) if lasts else None,
        })
    # 内容多的排前面，方便优先核查高产马甲
    out.sort(key=lambda r: (r["post_count"] + r["project_count"]), reverse=True)
    return out


def persona_recent_content(db: Session, persona_id: uuid.UUID, limit: int = 30):
    """某马甲最近的动态 + 项目（各取 limit 条，未删的），供逐条核查/删除。
    返回 (persona_user, posts, projects)；persona 不存在返回 (None, [], [])。"""
    user = db.get(User, persona_id)
    if user is None or user.deleted_at is not None:
        return None, [], []
    posts = list(db.execute(
        select(Post)
        .where(Post.author_user_id == persona_id, Post.deleted_at.is_(None))
        .order_by(Post.created_at.desc())
        .limit(limit)
    ).scalars())
    projects = list(db.execute(
        select(Project)
        .where(Project.author_user_id == persona_id, Project.deleted_at.is_(None))
        .order_by(Project.created_at.desc())
        .limit(limit)
    ).scalars())
    return user, posts, projects
