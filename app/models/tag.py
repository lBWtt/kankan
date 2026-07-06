# ============================================================
# 这个文件是干什么的：定义两张标签表——"标签字典"（所有出现过的标签词）
#   和"项目-标签关系"（哪个项目挂了哪些标签）。
# 它对应产品里的什么功能：卡片和详情页上的多彩标签、按标签搜索。
# 如果它出错了，用户会看到什么现象：项目卡片上标签消失，按标签搜不到内容。
# ============================================================
import uuid

from sqlalchemy import ForeignKey, Index, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, CreatedAtMixin, uuid_pk


class ProjectTag(CreatedAtMixin, Base):
    __tablename__ = "project_tags"

    id: Mapped[uuid.UUID] = uuid_pk()
    name: Mapped[str] = mapped_column(String(50), nullable=False, unique=True)


class ProjectTagRelation(CreatedAtMixin, Base):
    __tablename__ = "project_tag_relations"

    id: Mapped[uuid.UUID] = uuid_pk()
    project_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("projects.id"), nullable=False)
    tag_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("project_tags.id"), nullable=False)

    __table_args__ = (
        UniqueConstraint("project_id", "tag_id", name="uq_project_tag_relations_project_tag"),
        Index("ix_project_tag_relations_tag_id", "tag_id"),
    )
