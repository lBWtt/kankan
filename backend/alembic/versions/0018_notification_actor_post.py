"""notification actor_user_id + post_id (deep-link 关注/动态互动)

Revision ID: 0018_notification_actor_post
Revises: 0017_feedback
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "0018_notification_actor_post"
down_revision: Union[str, None] = "0017_feedback"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # 触发者（关注类通知点开跳 ta 的主页）；用户注销时置空、通知保留。
    op.add_column(
        "notifications",
        sa.Column("actor_user_id", sa.dialects.postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True),
    )
    # 动态落点（动态点赞/评论类通知点开跳该动态）；动态删除时置空、通知保留。
    op.add_column(
        "notifications",
        sa.Column("post_id", sa.dialects.postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("posts.id", ondelete="SET NULL"), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("notifications", "post_id")
    op.drop_column("notifications", "actor_user_id")
