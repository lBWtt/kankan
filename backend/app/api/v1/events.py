# ============================================================
# 这个文件是干什么的：埋点上报接口的路由——客户端把用户行为事件批量发进来，落埋点表。
# 它对应产品里的什么功能：数据看板主信号漏斗的曝光/点击类指标、热度分的浏览/点击权重。
# 如果它出错了，用户会看到什么现象：用户无感知，但漏斗数据断流、本周热门排序失真。
# ============================================================
from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import APIRouter, Depends, Request
from sqlalchemy.orm import Session

from app.api.deps import ERRORS_PUBLIC, auth_optional
from app.core.db import get_db
from app.core.redis import redis_client
from app.models import AnalyticsEvent, Project, User
from app.schemas.analytics import EventBatch, EventsAccepted

router = APIRouter(prefix="/events", tags=["埋点"], responses=ERRORS_PUBLIC)

# 反刷榜减速带：同一身份每 60 秒最多记这么多条事件，超出静默丢弃（不报错，埋点绝不阻断客户端）。
# 取 100 而非更小值：card_impression 是漏斗指标，活跃用户滚动信息流一分钟轻松几十条曝光，
# 阈值太低会把正常遥测一起丢、反而污染漏斗。这是减速带不是墙——攻击者轮换身份仍可绕过，
# 根治（曝光是否进 hot_score、事件去重/可见性校验）是更大的后续改动。可按需调这两个常量。
EVENTS_RATE_LIMIT = 100
EVENTS_RATE_WINDOW_SECONDS = 60


def _rate_identity(user: Optional[User], client_info: Optional[dict], request: Request) -> str:
    """限频身份键：优先登录用户，其次客户端匿名 ID，最后退化到来源 IP。
    反代部署下 request.client.host 是代理 IP，所有用户会共享一个身份被误限频，
    因此优先取 X-Forwarded-For 的第一个地址（仅用于限频，非鉴权，可接受被伪造的风险）。"""
    if user is not None:
        return f"u:{user.id}"
    anon = (client_info or {}).get("anon_client_id")
    if anon:
        return f"a:{str(anon)[:64]}"
    xff = request.headers.get("x-forwarded-for")
    if xff:
        ip = xff.split(",")[0].strip()
    else:
        ip = request.client.host if request.client else ""
    return f"ip:{ip or 'unknown'}"


def _over_event_rate(identity: str, n: int) -> bool:
    """滚动窗口计数：把本批条数累加进 60 秒桶，超阈值返回 True。
    Redis 不可用时返回 False——宁可放过也不阻断主流程（埋点不该因缓存抖动而失败）。"""
    key = f"events:rl:{identity}"
    try:
        total = redis_client.incrby(key, n)
        if total == n:  # 本窗口首次写入，设过期
            redis_client.expire(key, EVENTS_RATE_WINDOW_SECONDS)
        return total > EVENTS_RATE_LIMIT
    except Exception:
        return False


@router.post("", response_model=EventsAccepted, status_code=201,
             summary="批量上报行为事件（游客可用）")
def ingest_events(
    body: EventBatch,
    request: Request,
    user: Optional[User] = Depends(auth_optional),
    db: Session = Depends(get_db),
):
    """登录态自动带 user_id；游客把匿名 ID 放 client_info。事件时间以客户端 occurred_at 为准，
    但明显异常的（未来时间 / 超过 7 天前，多为设备时钟不准）改按服务端收到时间记。
    超出限频的批次静默丢弃（accepted=0），客户端不报错。"""
    identity = _rate_identity(user, body.client_info, request)
    if _over_event_rate(identity, len(body.events)):
        return EventsAccepted(accepted=0)

    now = datetime.now(timezone.utc)
    earliest = now - timedelta(days=7)
    accepted = 0
    for e in body.events:
        occurred = e.occurred_at
        if occurred is not None and occurred.tzinfo is None:
            occurred = occurred.replace(tzinfo=timezone.utc)
        if occurred is None or occurred > now + timedelta(minutes=5) or occurred < earliest:
            occurred = now

        # C-API-3(b): 校验 project_id 存在且 published 且未软删——
        # 防伪造/已删 project_id 灌脏数据进热度分漏斗。db.get 走 session 身份映射，同批重复 id 不重复查库。
        if e.project_id is not None:
            proj = db.get(Project, e.project_id)
            if proj is None or proj.status != "published" or proj.deleted_at is not None:
                continue

        # C-API-3(a): 曝光/详情事件 per-(project, identity) 日级 cap（200/天）——
        # 批量级频控按身份计数，攻击者轮换 anon_client_id 即可绕过；这里对进 hot_score 的
        # card_impression/detail_view 再按 (project, identity) 日级封顶，超出静默丢弃（不抛 429，
        # 埋点绝不阻断客户端）。identity 复用批量级身份（登录>anon_client_id>IP），anon_client_id 来自 client_info。
        if e.event_name in ("card_impression", "detail_view") and e.project_id is not None:
            pkey = f"events:proj:{e.project_id}:{identity}"
            try:
                n = redis_client.incr(pkey)
                if n == 1:
                    redis_client.expire(pkey, 86400)
                if n > 200:
                    continue  # 静默丢弃本条，不影响同批其余事件
            except Exception:
                pass  # fail-open：Redis 抖动不阻断埋点入库

        db.add(
            AnalyticsEvent(
                user_id=user.id if user else None,
                event_name=e.event_name,
                project_id=e.project_id,
                event_payload=e.payload,
                client_info=body.client_info,
                created_at=occurred,
            )
        )
        accepted += 1
    db.commit()
    return EventsAccepted(accepted=accepted)
