# ============================================================
# 这个文件是干什么的：所有数据表的"地基"——规定每张表的通用部件：
#   UUID 主键怎么生成、创建/更新时间怎么记、约束怎么自动命名。
# 它对应产品里的什么功能：不对应单一功能，是 18 张表共同遵守的规矩。
# 如果它出错了，用户会看到什么现象：建库直接失败，开发者一张表都建不出来。
# ============================================================
import uuid
from datetime import datetime

from sqlalchemy import MetaData, text
from sqlalchemy.dialects.postgresql import TIMESTAMP, UUID
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column
from sqlalchemy.sql import func

# 约束/索引自动命名规则：保证模型和迁移脚本生成的名字一致，方便日后修改
NAMING_CONVENTION = {
    "ix": "ix_%(column_0_label)s",
    "uq": "uq_%(table_name)s_%(column_0_name)s",
    "ck": "ck_%(table_name)s_%(constraint_name)s",
    "fk": "fk_%(table_name)s_%(column_0_name)s_%(referred_table_name)s",
    "pk": "pk_%(table_name)s",
}


class Base(DeclarativeBase):
    metadata = MetaData(naming_convention=NAMING_CONVENTION)


def uuid_pk() -> Mapped[uuid.UUID]:
    """UUID 主键：由数据库自动生成（PostgreSQL 16 内置 gen_random_uuid）。"""
    return mapped_column(UUID(as_uuid=True), primary_key=True, server_default=text("gen_random_uuid()"))


class CreatedAtMixin:
    """只记"创建时间"的表用这个（如收藏、点赞这类一次性动作记录）。"""

    created_at: Mapped[datetime] = mapped_column(
        TIMESTAMP(timezone=True), server_default=func.now(), nullable=False
    )


class TimestampMixin(CreatedAtMixin):
    """既记创建时间也记最后修改时间的表用这个（如用户、项目）。"""

    updated_at: Mapped[datetime] = mapped_column(
        TIMESTAMP(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )
