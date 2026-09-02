"""add topic follow relationships

Revision ID: 0014_topic_follows
Revises: 0013_project_try_url
Create Date: 2026-07-15 00:00:00
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "0014_topic_follows"
down_revision: Union[str, None] = "0013_project_try_url"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "topic_follows",
        sa.Column("id", postgresql.UUID(as_uuid=True), server_default=sa.text("gen_random_uuid()"), nullable=False),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("tag", sa.Text(), nullable=False),
        sa.Column("created_at", postgresql.TIMESTAMP(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.CheckConstraint("length(btrim(tag)) BETWEEN 1 AND 64", name="ck_topic_follows_valid_tag"),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("user_id", "tag", name="uq_topic_follows_user_tag"),
    )
    op.create_index("ix_topic_follows_user_created", "topic_follows", ["user_id", "created_at"])


def downgrade() -> None:
    op.drop_index("ix_topic_follows_user_created", table_name="topic_follows")
    op.drop_table("topic_follows")
