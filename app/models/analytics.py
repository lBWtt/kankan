# ============================================================
# 这个文件是干什么的：定义"埋点事件表"——用户在 App 里的每个动作
#   （看了卡片、点了详情、搜索了什么）都记一条流水。
# 它对应产品里的什么功能：热度分（hot_score）里的浏览/点击权重靠它算；
#   主信号漏斗（想看怎么做转化率）的数据看板也靠它。
# 如果它出错了，用户会看到什么现象：用户无感知，但热门榜单失真、
#   运营完全看不到产品核心假设是否成立的数据。
# ============================================================
import uuid
from typing import Optional

from sqlalchemy import Index, String
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, CreatedAtMixin, uuid_pk


class AnalyticsEvent(CreatedAtMixin, Base):
    __tablename__ = "analytics_events"

    id: Mapped[uuid.UUID] = uuid_pk()
    # 埋点表高频写入且允许游客事件，所以 user_id/project_id 不设外键、可空（字段·API v1.3 §10）
    user_id: Mapped[Optional[uuid.UUID]] = mapped_column(UUID(as_uuid=True))
    # 事件名 snake_case 英文（PRD §13.5）：app_open / card_click / how_to_interest / clue_subscribe ...
    event_name: Mapped[str] = mapped_column(String(50), nullable=False)
    project_id: Mapped[Optional[uuid.UUID]] = mapped_column(UUID(as_uuid=True))
    # 事件属性（如 reaction type、搜索词）；客户端信息（设备、版本、匿名 ID、粗粒度地区）
    event_payload: Mapped[Optional[dict]] = mapped_column(JSONB)
    client_info: Mapped[Optional[dict]] = mapped_column(JSONB)

    __table_args__ = (
        Index("ix_analytics_events_name_created", "event_name", "created_at"),
        Index("ix_analytics_events_project_id", "project_id"),
    )
