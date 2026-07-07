# ============================================================
# 这个文件是干什么的：定义"分享记录表"——谁（包括游客）把哪个项目分享到了哪个渠道，
#   分两步记录：点了分享(clicked)、确认分享完成(completed)。
# 它对应产品里的什么功能：分享卡、分享回流增长，以及热度分里的 share_completed×6 权重。
# 如果它出错了，用户会看到什么现象：用户自己没感觉，但热门榜单会失真，运营看不到分享转化数据。
# ============================================================
import uuid
from typing import Optional

from sqlalchemy import ForeignKey, Index, String
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, CreatedAtMixin, uuid_pk
from app.models.enums import share_channel_enum, share_status_enum


class Share(CreatedAtMixin, Base):
    __tablename__ = "shares"

    id: Mapped[uuid.UUID] = uuid_pk()
    # 游客也能分享，所以 user_id 可空，游客用 anon_client_id（补全决策，对齐 how_to_interests 的做法）
    # C-MDL-3：ondelete=CASCADE——用户/项目删除时分享记录随删
    user_id: Mapped[Optional[uuid.UUID]] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    anon_client_id: Mapped[Optional[str]] = mapped_column(String(64))
    project_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("projects.id", ondelete="CASCADE"), nullable=False)
    share_channel: Mapped[str] = mapped_column(share_channel_enum, nullable=False)
    share_status: Mapped[str] = mapped_column(share_status_enum, nullable=False)

    __table_args__ = (
        # 字段·API v1.3 §11：统计用复合索引
        Index("ix_shares_project_status_channel", "project_id", "share_status", "share_channel"),
    )
