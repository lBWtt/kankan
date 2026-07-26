# ============================================================
# 这个文件是干什么的：定义「意见反馈表」——用户提的 bug / 优化建议，带自动采集的
#   App 版本 / 机型等排障信息，运营在后台看和处理。
# 它对应产品里的什么功能：设置/我的页的「意见反馈」入口、后台的反馈处理队列。
# 如果它出错了，用户会看到什么现象：反馈提交失败，或早期用户报的 bug 没人看见。
# ============================================================
import uuid
from datetime import datetime
from typing import Optional

from sqlalchemy import CheckConstraint, ForeignKey, Index, String, Text
from sqlalchemy.dialects.postgresql import TIMESTAMP
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, TimestampMixin, uuid_pk


class Feedback(TimestampMixin, Base):
    __tablename__ = "feedbacks"

    id: Mapped[uuid.UUID] = uuid_pk()
    # 反馈允许游客提交（早期用户可能没登录）；登录则带 user_id。
    # C-MDL-3：ondelete=SET NULL——用户注销时反馈保留（排障线索不丢），user_id 置空。
    user_id: Mapped[Optional[uuid.UUID]] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
    # 分类：bug 故障 / suggestion 优化建议 / other 其他
    category: Mapped[str] = mapped_column(String(20), nullable=False, server_default="bug")
    content: Mapped[str] = mapped_column(Text, nullable=False)
    contact: Mapped[Optional[str]] = mapped_column(String(100))  # 选填：用户留的联系方式
    # 自动采集的排障信息（客户端带上来）：App 版本、平台、机型
    app_version: Mapped[Optional[str]] = mapped_column(String(40))
    platform: Mapped[Optional[str]] = mapped_column(String(20))
    device_info: Mapped[Optional[str]] = mapped_column(String(200))
    source_page: Mapped[Optional[str]] = mapped_column(String(120))
    error_code: Mapped[Optional[str]] = mapped_column(String(80))
    # 处理流转：new 待处理 / handled 已处理
    status: Mapped[str] = mapped_column(String(20), nullable=False, server_default="new")
    handled_by_user_id: Mapped[Optional[uuid.UUID]] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
    handled_at: Mapped[Optional[datetime]] = mapped_column(TIMESTAMP(timezone=True))
    admin_note: Mapped[Optional[str]] = mapped_column(Text)

    __table_args__ = (
        Index("ix_feedbacks_status_created_at", "status", "created_at"),
        CheckConstraint("category IN ('bug','suggestion','other')", name="ck_feedback_category"),
        CheckConstraint("status IN ('new','handled')", name="ck_feedback_status"),
    )
