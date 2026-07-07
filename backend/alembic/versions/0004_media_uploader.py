# ============================================================
# 这个文件是干什么的：第四份"改库图纸"——给项目媒体表加 uploader_user_id（上传者）列，
#   让发布挂载时能校验"这张暂存图是不是你本人传的"。
# 它对应产品里的什么功能：发布页挂图的越权防护——别人传的未挂载媒体你挂不上。
# 如果它出错了，用户会看到什么现象：要么发布挂图报错，要么越权漏洞没堵上（能挂别人的图）。
# ============================================================
"""media uploader ownership

Revision ID: 0004
Revises: 0003
Create Date: 2026-06-13

"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "0004"
down_revision: Union[str, None] = "0003"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "project_media",
        sa.Column("uploader_user_id", postgresql.UUID(as_uuid=True), nullable=True),
    )
    op.create_foreign_key(
        "fk_project_media_uploader", "project_media", "users",
        ["uploader_user_id"], ["id"],
    )
    op.create_index("ix_project_media_uploader", "project_media", ["uploader_user_id"])


def downgrade() -> None:
    op.drop_index("ix_project_media_uploader", table_name="project_media")
    op.drop_constraint("fk_project_media_uploader", "project_media", type_="foreignkey")
    op.drop_column("project_media", "uploader_user_id")
