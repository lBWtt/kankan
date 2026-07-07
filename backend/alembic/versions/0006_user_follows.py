# ============================================================
# 这个文件是干什么的：第六份改库图纸，建"关注关系"表 user_follows。
# 它对应产品里的什么功能：用户互相关注（我的页关注/粉丝数、关注按钮、关注列表）。
# 如果它出错了，用户会看到什么现象：迁移失败，或关注功能无法使用。
# ============================================================
"""user follows

Revision ID: 0006
Revises: 0005
Create Date: 2026-07-07

"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "0006"
down_revision: Union[str, None] = "0005"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "user_follows",
        sa.Column("id", postgresql.UUID(as_uuid=True), server_default=sa.text("gen_random_uuid()"), nullable=False),
        sa.Column("follower_user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("followee_user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.ForeignKeyConstraint(["follower_user_id"], ["users.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["followee_user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("follower_user_id", "followee_user_id", name="uq_user_follows_pair"),
    )
    op.create_index("ix_user_follows_followee", "user_follows", ["followee_user_id"])


def downgrade() -> None:
    op.drop_index("ix_user_follows_followee", table_name="user_follows")
    op.drop_table("user_follows")
