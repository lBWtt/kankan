import uuid

from sqlalchemy import CheckConstraint, ForeignKey, Index, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, CreatedAtMixin, uuid_pk


class TopicFollow(CreatedAtMixin, Base):
    """A user's subscription to an aggregate topic tag."""

    __tablename__ = "topic_follows"

    id: Mapped[uuid.UUID] = uuid_pk()
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    tag: Mapped[str] = mapped_column(Text, nullable=False)

    __table_args__ = (
        UniqueConstraint("user_id", "tag", name="uq_topic_follows_user_tag"),
        CheckConstraint("length(btrim(tag)) BETWEEN 1 AND 64", name="valid_tag"),
        Index("ix_topic_follows_user_created", "user_id", "created_at"),
    )
