# ============================================================
# 这个文件是干什么的：定义"管理员操作日志表"——后台每一次下架、删除、通过审核等
#   操作都留一条记录，记下谁、何时、对什么、做了什么。
# 它对应产品里的什么功能：后台的"操作日志"页，出问题时追责回溯用。
# 如果它出错了，用户会看到什么现象：用户无感知，但运营出错时（如误下架）将无法追查是谁操作的。
# ============================================================
import uuid
from typing import Optional

from sqlalchemy import ForeignKey, Index, String
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, CreatedAtMixin, uuid_pk


class AdminAction(CreatedAtMixin, Base):
    __tablename__ = "admin_actions"

    id: Mapped[uuid.UUID] = uuid_pk()
    admin_user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id"), nullable=False)
    # 动作名：take_down / restore / soft_delete / approve / discard / require_edit / feature / resolve_report ...
    action: Mapped[str] = mapped_column(String(50), nullable=False)
    # 操作对象：project / candidate / report / user（不设外键，因为对象可能在不同表）
    target_type: Mapped[str] = mapped_column(String(30), nullable=False)
    target_id: Mapped[Optional[uuid.UUID]] = mapped_column(UUID(as_uuid=True))
    # 附加细节（如下架理由、修改前后的值）
    detail: Mapped[Optional[dict]] = mapped_column(JSONB)

    __table_args__ = (
        Index("ix_admin_actions_admin_created", "admin_user_id", "created_at"),
        Index("ix_admin_actions_target", "target_type", "target_id"),
    )
