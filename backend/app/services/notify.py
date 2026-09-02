# ============================================================
# 这个文件是干什么的：站内互动通知的**统一出口**——关注/点赞/评论等社交动作发生时，
#   给被互动的人写一条 type=interaction 的通知。集中一处，保证三条铁律一致：
#   ① 不通知自己（自己赞自己/评论自己不提醒）；② 尊重用户的推送开关（interaction_enabled）；
#   ③ 只入 session 不 commit——挂在调用方的事务里，动作回滚（如重复关注）通知一并作废。
# 它对应产品里的什么功能：通知中心里的「XX 关注了你 / 赞了你的作品 / 评论了你」。
# 如果它出错了：用户互动后对方收不到提醒（多账号模拟时看不到反馈），或自己给自己发通知。
# ============================================================
import uuid
from typing import Optional

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import Notification, PushPreference, User


def push_interaction(
    db: Session,
    *,
    recipient_id: Optional[uuid.UUID],
    actor: Optional[User],
    title: str,
    body: Optional[str] = None,
    project_id: Optional[uuid.UUID] = None,
    post_id: Optional[uuid.UUID] = None,
) -> None:
    """给 recipient 写一条互动通知（不 commit，挂在调用方事务里）。
    - recipient 为空、或就是 actor 本人 → 不发（不通知自己）。
    - recipient 关了互动推送（PushPreference.interaction_enabled=False）→ 不发。
    深链落点（前端据此跳转）：project_id=作品详情 / post_id=动态详情 / 都无但有 actor=触发者主页（关注类）。
    actor 一并落 actor_user_id，前端也用它显示触发者头像。"""
    if recipient_id is None:
        return
    if actor is not None and recipient_id == actor.id:
        return
    pref = db.scalar(select(PushPreference).where(PushPreference.user_id == recipient_id))
    if pref is not None and not pref.interaction_enabled:
        return
    db.add(Notification(
        user_id=recipient_id,
        type="interaction",
        title=title[:200],
        body=body,
        project_id=project_id,
        post_id=post_id,
        actor_user_id=actor.id if actor is not None else None,
    ))
