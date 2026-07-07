# ============================================================
# 这个文件是干什么的：定义"举报表"——谁举报了哪个项目、为什么、处理到哪一步了。
# 它对应产品里的什么功能：详情页的举报弹窗、后台的举报处理队列。
# 如果它出错了，用户会看到什么现象：举报提交失败，或违规内容迟迟不被处理。
# ============================================================
import uuid
from datetime import datetime
from typing import Optional

from sqlalchemy import CheckConstraint, ForeignKey, Index, String, Text
from sqlalchemy.dialects.postgresql import TIMESTAMP
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, TimestampMixin, uuid_pk
from app.models.enums import report_status_enum


class Report(TimestampMixin, Base):
    __tablename__ = "reports"

    id: Mapped[uuid.UUID] = uuid_pk()
    # 举报需登录（页面地图 §3 登录拦截点）
    # C-MDL-3：ondelete=CASCADE——举报人/项目删除时举报记录随删
    reporter_user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    project_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("projects.id", ondelete="CASCADE"), nullable=False)
    # 举报原因分类 + 详细描述（补全决策：v1.2 原文不可得，按后台文档举报回路推断）
    reason: Mapped[str] = mapped_column(String(50), nullable=False)
    description: Mapped[Optional[str]] = mapped_column(Text)
    status: Mapped[str] = mapped_column(report_status_enum, nullable=False, server_default="pending")
    # C-MDL-3：ondelete=SET NULL——处理人注销时举报保留，handled_by 置空（保留审计链）
    handled_by_user_id: Mapped[Optional[uuid.UUID]] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
    handled_at: Mapped[Optional[datetime]] = mapped_column(TIMESTAMP(timezone=True))
    resolution_note: Mapped[Optional[str]] = mapped_column(Text)

    __table_args__ = (
        Index("ix_reports_status_created_at", "status", "created_at"),
        Index("ix_reports_project_id", "project_id"),
        # H-MDL-5：举报原因白名单 CHECK（与 schemas/interaction.ReportReason 枚举一致）
        CheckConstraint(
            "reason IN ('copyright','ad_spam','nsfw','low_quality','other')",
            name="report_reason_allowed",
        ),
    )
