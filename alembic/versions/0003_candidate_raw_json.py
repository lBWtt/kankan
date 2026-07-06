# ============================================================
# 这个文件是干什么的：第三份"改库图纸"——候选池表加 raw_json 列，存抓取回来的原始内容
#   （原文标题、原始正文、媒体链接、抓取时间），AI 整理时读它，整理后也不删（留审计+保留原文）。
# 它对应产品里的什么功能：AI 抓取管线的"原料仓"；PRD §10 外文处理要求保留原文标题。
# 如果它出错了，用户会看到什么现象：抓回来的内容无处可存，候选池断供，App 新内容停更。
# ============================================================
"""candidate raw_json for crawled source material

Revision ID: 0003
Revises: 0002
Create Date: 2026-06-12

"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "0003"
down_revision: Union[str, None] = "0002"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # 抓取原料：{"title": 原文标题, "text": 原始正文, "media": [url...], "fetched_at": ...}
    op.add_column("candidate_contents", sa.Column("raw_json", postgresql.JSONB(), nullable=True))


def downgrade() -> None:
    op.drop_column("candidate_contents", "raw_json")
