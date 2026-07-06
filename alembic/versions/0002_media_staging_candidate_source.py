# ============================================================
# 这个文件是干什么的：第二份"改库图纸"——两处小改动：①媒体表的 project_id 改为可空
#   （用户先传图、后建项目的暂存态）；②候选池补 source_type 字段（漏检修正）。
# 它对应产品里的什么功能：发布页"先传图后发布"的流程、候选审核时区分 AI 抓取/手动导入。
# 如果它出错了，用户会看到什么现象：图片传不上去（发不了项目），候选无法正确标注来源。
# ============================================================
"""media staging + candidate source_type

Revision ID: 0002
Revises: 0001
Create Date: 2026-06-10

"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "0002"
down_revision: Union[str, None] = "0001"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # 媒体先上传后挂载：project_id 允许为空（空=暂存，发布时回填）
    op.alter_column(
        "project_media", "project_id", existing_type=postgresql.UUID(as_uuid=True), nullable=True
    )
    # 候选池补来源类型（0001 漏检：approve 复制进 projects 时需要它）
    op.add_column(
        "candidate_contents",
        sa.Column(
            "source_type",
            postgresql.ENUM(name="content_source_type", create_type=False),
            nullable=False,
            server_default="ai_crawled",
        ),
    )


def downgrade() -> None:
    op.drop_column("candidate_contents", "source_type")
    # 回滚前清掉暂存态媒体，否则 NOT NULL 加不回去
    op.execute("DELETE FROM project_media WHERE project_id IS NULL")
    op.alter_column(
        "project_media", "project_id", existing_type=postgresql.UUID(as_uuid=True), nullable=False
    )
