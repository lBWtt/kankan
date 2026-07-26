"""candidate try_url（体验链接，DeepSeek 从原文提取，approve 带进项目）

Revision ID: 0019_candidate_try_url
Revises: 0018_notification_actor_post
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "0019_candidate_try_url"
down_revision: Union[str, None] = "0018_notification_actor_post"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # 体验入口：DeepSeek 从原文提取的可去试链接/小程序名/公众号；approve 时带进 Project.try_url。
    op.add_column("candidate_contents", sa.Column("try_url", sa.Text(), nullable=True))


def downgrade() -> None:
    op.drop_column("candidate_contents", "try_url")
