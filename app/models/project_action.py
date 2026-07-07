# ============================================================
# 这个文件是干什么的：记录新版项目详情页里的“能做什么”按钮，以及用户点了之后的流水。
# 它对应产品里的什么功能：详情页下方的拿走、去看看、看怎么做这些动作入口。
# 如果它出错了，用户会看到什么现象：按钮丢失、点击不计数，或者榜单热度少算真实行动。
# ============================================================
import uuid
from typing import Optional

from sqlalchemy import CheckConstraint, ForeignKey, Index, Integer, String, Text, text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, CreatedAtMixin, uuid_pk


class ProjectAction(CreatedAtMixin, Base):
    __tablename__ = "project_actions"

    id: Mapped[uuid.UUID] = uuid_pk()
    # C-MDL-3：ondelete=CASCADE——项目删除时其动作按钮随删
    project_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("projects.id", ondelete="CASCADE"), nullable=False)
    action_type: Mapped[str] = mapped_column(String(20), nullable=False)
    action_sub: Mapped[str] = mapped_column(String(20), nullable=False)
    label: Mapped[str] = mapped_column(String(255), nullable=False)
    sublabel: Mapped[Optional[str]] = mapped_column(String(255))
    content: Mapped[Optional[str]] = mapped_column(Text)
    # C-MDL-3：ondelete=SET NULL——媒体被删时动作按钮保留，file_media_id 置空（动作降级为无附件）
    file_media_id: Mapped[Optional[uuid.UUID]] = mapped_column(UUID(as_uuid=True), ForeignKey("project_media.id", ondelete="SET NULL"))
    file_name: Mapped[Optional[str]] = mapped_column(String(255))
    file_size_bytes: Mapped[Optional[int]] = mapped_column(Integer)
    url: Mapped[Optional[str]] = mapped_column(Text)
    sort_order: Mapped[int] = mapped_column(Integer, nullable=False, server_default=text("0"))

    __table_args__ = (
        CheckConstraint("action_type IN ('take', 'go', 'how')", name="project_action_type_allowed"),
        CheckConstraint(
            "action_sub IN ('text', 'file', 'github', 'appstore', 'url', 'workflow')",
            name="project_action_sub_allowed",
        ),
        Index("ix_project_actions_project_id", "project_id"),
        Index("ix_project_actions_file_media_id", "file_media_id"),
    )


class ProjectActionEvent(CreatedAtMixin, Base):
    __tablename__ = "project_action_events"

    id: Mapped[uuid.UUID] = uuid_pk()
    # C-MDL-3：ondelete=CASCADE——项目/动作/用户删除时事件流水随删
    project_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("projects.id", ondelete="CASCADE"), nullable=False)
    action_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("project_actions.id", ondelete="CASCADE"), nullable=False)
    user_id: Mapped[Optional[uuid.UUID]] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    anon_client_id: Mapped[Optional[str]] = mapped_column(String(64))
    event_type: Mapped[str] = mapped_column(String(20), nullable=False)

    __table_args__ = (
        CheckConstraint("event_type IN ('click', 'success')", name="project_action_event_type_allowed"),
        CheckConstraint(
            "user_id IS NOT NULL OR anon_client_id IS NOT NULL",
            name="project_action_event_has_actor",
        ),
        Index("ix_project_action_events_project_created", "project_id", "created_at"),
        Index("ix_project_action_events_action_created", "action_id", "created_at"),
        Index("ix_project_action_events_user_created", "user_id", "created_at"),
        Index("ix_project_action_events_anon_created", "anon_client_id", "created_at"),
    )
