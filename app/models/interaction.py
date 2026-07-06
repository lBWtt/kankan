# ============================================================
# 这个文件是干什么的：定义 6 张"用户动作表"——收藏、想试、想看怎么做（游客也能点）、
#   线索订阅、"我做了类似的"关联、创意反馈。
# 它对应产品里的什么功能：产品的全部互动按钮；其中"想看怎么做"是全产品的主信号，
#   热度分和需求看板都靠这些表算出来。
# 如果它出错了，用户会看到什么现象：点收藏/想试没反应或重复计数，
#   热门榜单排序失真，作者收不到"有人想看怎么做"的通知。
# ============================================================
import uuid
from typing import Optional

from sqlalchemy import CheckConstraint, ForeignKey, Index, String, UniqueConstraint, text
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, CreatedAtMixin, uuid_pk
from app.models.enums import reaction_type_enum


class Favorite(CreatedAtMixin, Base):
    """收藏：需登录，同一人对同一项目只能收藏一次。"""

    __tablename__ = "favorites"

    id: Mapped[uuid.UUID] = uuid_pk()
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id"), nullable=False)
    project_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("projects.id"), nullable=False)

    __table_args__ = (
        UniqueConstraint("user_id", "project_id", name="uq_favorites_user_project"),
        Index("ix_favorites_project_id", "project_id"),
    )


class TryItem(CreatedAtMixin, Base):
    """想试：需登录，驱动"新版本通知"。结构同收藏。"""

    __tablename__ = "try_items"

    id: Mapped[uuid.UUID] = uuid_pk()
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id"), nullable=False)
    project_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("projects.id"), nullable=False)

    __table_args__ = (
        UniqueConstraint("user_id", "project_id", name="uq_try_items_user_project"),
        Index("ix_try_items_project_id", "project_id"),
    )


class HowToInterest(CreatedAtMixin, Base):
    """想看怎么做（主信号）。红线：user_id 必须可空——游客用 anon_client_id 记录，绝不设登录墙。
    去重规则（部分唯一索引在迁移脚本里建）：登录用户按 (user_id, project_id) 去重，
    游客按 (anon_client_id, project_id) 去重。"""

    __tablename__ = "how_to_interests"

    id: Mapped[uuid.UUID] = uuid_pk()
    user_id: Mapped[Optional[uuid.UUID]] = mapped_column(ForeignKey("users.id"))
    anon_client_id: Mapped[Optional[str]] = mapped_column(String(64))
    project_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("projects.id"), nullable=False)

    __table_args__ = (
        # 登录或游客身份至少要有一个，否则这条需求无法去重也无法统计
        CheckConstraint("user_id IS NOT NULL OR anon_client_id IS NOT NULL", name="identity_present"),
        Index(
            "uq_how_to_interests_user_project",
            "user_id",
            "project_id",
            unique=True,
            postgresql_where=text("user_id IS NOT NULL"),
        ),
        Index(
            "uq_how_to_interests_anon_project",
            "anon_client_id",
            "project_id",
            unique=True,
            postgresql_where=text("user_id IS NULL"),
        ),
        Index("ix_how_to_interests_project_id", "project_id"),
    )


class ClueSubscription(CreatedAtMixin, Base):
    """实现线索页的"订阅更新"：需登录，防重复订阅。"""

    __tablename__ = "clue_subscriptions"

    id: Mapped[uuid.UUID] = uuid_pk()
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id"), nullable=False)
    project_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("projects.id"), nullable=False)

    __table_args__ = (
        UniqueConstraint("user_id", "project_id", name="uq_clue_subscriptions_user_project"),
        Index("ix_clue_subscriptions_project_id", "project_id"),
    )


class SimilarProjectLink(CreatedAtMixin, Base):
    """「我做了类似的」单向关联：source=原项目 A，similar=新作品 B。"""

    __tablename__ = "similar_project_links"

    id: Mapped[uuid.UUID] = uuid_pk()
    source_project_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("projects.id"), nullable=False)
    similar_project_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("projects.id"), nullable=False)

    __table_args__ = (
        UniqueConstraint("source_project_id", "similar_project_id", name="uq_similar_links_source_similar"),
        Index("ix_similar_links_source", "source_project_id"),
        Index("ix_similar_links_similar", "similar_project_id"),
    )


class ProjectReaction(CreatedAtMixin, Base):
    """创意反馈（有创意/太聪明了/酷）：需登录、可取消（取消=删行），同类反应一人一次。"""

    __tablename__ = "project_reactions"

    id: Mapped[uuid.UUID] = uuid_pk()
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id"), nullable=False)
    project_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("projects.id"), nullable=False)
    reaction_type: Mapped[str] = mapped_column(reaction_type_enum, nullable=False)

    __table_args__ = (
        UniqueConstraint("user_id", "project_id", "reaction_type", name="uq_reactions_user_project_type"),
        Index("ix_project_reactions_project_id", "project_id"),
    )


class UserFollow(CreatedAtMixin, Base):
    """关注关系：follower 关注 followee。同一对只能关注一次；不能关注自己（服务层校验）。
    外键带 ON DELETE CASCADE：用户注销时其关注/被关注关系随删。"""

    __tablename__ = "user_follows"

    id: Mapped[uuid.UUID] = uuid_pk()
    follower_user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    followee_user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )

    __table_args__ = (
        UniqueConstraint("follower_user_id", "followee_user_id", name="uq_user_follows_pair"),
        Index("ix_user_follows_followee", "followee_user_id"),
    )
