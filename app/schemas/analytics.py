# ============================================================
# 这个文件是干什么的：定义埋点上报接口的数据形状——客户端批量上报用户行为事件
#   （看了卡片、点了详情、点了线索页链接等）。
# 它对应产品里的什么功能：数据看板的主信号漏斗、热度分里的浏览/点击权重，全靠这些事件。
# 如果它出错了，用户会看到什么现象：用户无感知，但运营看不到漏斗数据、热门榜单失真。
# ============================================================
import uuid
from datetime import datetime, timedelta, timezone
from typing import List, Optional

from pydantic import BaseModel, Field, field_validator


class EventIn(BaseModel):
    """单条事件。事件名 snake_case 英文（字段·API v1.3 §10 核心清单：card_impression /
    card_click / detail_view / clue_source_click …）；不做硬白名单，新事件可直接上报。"""

    event_name: str = Field(min_length=2, max_length=50, pattern=r"^[a-z][a-z0-9_]*$")
    project_id: Optional[uuid.UUID] = None
    payload: Optional[dict] = Field(None, description="事件属性，如 reaction type、搜索词")
    occurred_at: Optional[datetime] = Field(
        None, description="客户端发生时间；缺省或明显异常（未来/超过 7 天前）按服务端收到时间记"
    )

    @field_validator("occurred_at", mode="after")
    @classmethod
    def _clamp_occurred_at(cls, v):
        """H-MDL-11：把"未来时间"或"超过 7 天前"的异常时间置 None，
        服务端落库时改用 now() 兜底——既兑现字段注释的承诺，又防恶意时间注入。"""
        if v is None:
            return v
        now = datetime.now(timezone.utc)
        # 若 v 是 naive datetime，按 UTC 解释以便比较
        v_aware = v if v.tzinfo is not None else v.replace(tzinfo=timezone.utc)
        if v_aware > now or v_aware < now - timedelta(days=7):
            return None
        return v


class EventBatch(BaseModel):
    """POST /events：批量上报（客户端攒一批一起发，省电省流量）。游客可用，无登录墙。"""

    events: List[EventIn] = Field(min_length=1, max_length=50)
    client_info: Optional[dict] = Field(None, description="设备、版本、匿名 ID、粗粒度地区（整批共用）")


class EventsAccepted(BaseModel):
    ok: bool = True
    accepted: int = Field(description="本批入库的事件条数")
