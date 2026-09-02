# ============================================================
# 这个文件是干什么的：定义两张表——"通知表"（发给用户的每条站内消息）
#   和"推送偏好表"（每个用户想收/不想收哪几类推送）。
# 它对应产品里的什么功能：通知中心、每日精选推送、"有人想试你的作品"提醒、
#   设置页的推送开关。
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
    # C-MDL-3：ondelete=CASCADE——用户删除时通知随删；项目删除时关联通知随删
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    type: Mapped[str] = mapped_column(notification_type_enum, nullable=False)
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    body: Mapped[Optional[str]] = mapped_column(Text)
    # 点开落点：通知→项目详情；want_to_try→「想试的人」页
    project_id: Mapped[Optional[uuid.UUID]] = mapped_column(ForeignKey("projects.id", ondelete="CASCADE"))
    # 互动通知深链（迁移 0018）：actor=触发者（关注类跳 ta 主页）；post=动态（动态互动跳该动态）。
    # ondelete=SET NULL：触发者/动态删除时通知保留、字段置空。
    actor_user_id: Mapped[Optional[uuid.UUID]] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
    post_id: Mapped[Optional[uuid.UUID]] = mapped_column(ForeignKey("posts.id", ondelete="SET NULL"))
    is_read: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default=text("false"))
    read_at: Mapped[Optional[datetime]] = mapped_column(TIMESTAMP(timezone=True))

    __table_args__ = (
        Index("ix_notifications_user_read_created", "user_id", "is_read", "created_at"),
    )


class PushPreference(TimestampMixin, Base):
    """每用户一行，7 个通知类型各一个开关，默认全开。"""

    __tablename__ = "push_preferences"

    id: Mapped[uuid.UUID] = uuid_pk()
    # C-MDL-3：ondelete=CASCADE——用户删除时推送偏好随删
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False, unique=True)
    daily_pick_enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default=text("true"))
    weekly_ranking_enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default=text("true"))
    # 列名保留 how_to_interest_enabled（内部无所谓；语义=想试/want_to_try）；已删 clue_update_enabled。
    how_to_interest_enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default=text("true"))
    similar_project_enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default=text("true"))
    content_status_enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default=text("true"))
    system_enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default=text("true"))
    interaction_enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default=text("true"))
