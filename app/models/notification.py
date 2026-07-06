# ============================================================
# 这个文件是干什么的：定义两张表——"通知表"（发给用户的每条站内消息）
#   和"推送偏好表"（每个用户想收/不想收哪几类推送）。
# 它对应产品里的什么功能：通知中心、每日精选推送、"有人想看你怎么做"提醒、
#   线索更新提醒、设置页的推送开关。
# 如果它出错了，用户会看到什么现象：收不到任何通知，或关掉的推送照样轰炸用户。
# ============================================================
import uuid
from datetime import datetime
from typing import Optional

from sqlalchemy import Boolean, ForeignKey, Index, String, Text, text
from sqlalchemy.dialects.postgresql import TIMESTAMP
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, CreatedAtMixin, TimestampMixin, uuid_pk
from app.models.enums import notification_type_enum


class Notification(CreatedAtMixin, Base):
    __tablename__ = "notifications"

    id: Mapped[uuid.UUID] = uuid_pk()
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id"), nullable=False)
    type: Mapped[str] = mapped_column(notification_type_enum, nullable=False)
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    body: Mapped[Optional[str]] = mapped_column(Text)
    # 点开落点：普通通知→项目详情；clue_update→实现线索页（页面地图 §3）
    project_id: Mapped[Optional[uuid.UUID]] = mapped_column(ForeignKey("projects.id"))
    is_read: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default=text("false"))
    read_at: Mapped[Optional[datetime]] = mapped_column(TIMESTAMP(timezone=True))

    __table_args__ = (
        Index("ix_notifications_user_read_created", "user_id", "is_read", "created_at"),
    )


class PushPreference(TimestampMixin, Base):
    """每用户一行，8 个通知类型各一个开关，默认全开。"""

    __tablename__ = "push_preferences"

    id: Mapped[uuid.UUID] = uuid_pk()
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id"), nullable=False, unique=True)
    daily_pick_enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default=text("true"))
    weekly_ranking_enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default=text("true"))
    how_to_interest_enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default=text("true"))
    clue_update_enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default=text("true"))
    similar_project_enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default=text("true"))
    content_status_enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default=text("true"))
    system_enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default=text("true"))
    interaction_enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default=text("true"))
