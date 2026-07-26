# ============================================================
# 第十三份改库图纸：projects 加 try_url（体验链接）列。
#   作者自己作品的可去用地址（网站/app），前端「去体验」直接打开；
#   与 source_url（采集源，不展示、不留出处）分开。
# 定位：展示作品→让别人直接去用。可空（草稿/采集内容没有）。
# ============================================================
"""add projects.try_url (experience link)

Revision ID: 0013_project_try_url
Revises: 0012_drop_clue_concepts
Create Date: 2026-07-13 00:00:00

"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "0013_project_try_url"
down_revision: Union[str, None] = "0012_drop_clue_concepts"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("projects", sa.Column("try_url", sa.Text(), nullable=True))


def downgrade() -> None:
    op.drop_column("projects", "try_url")
