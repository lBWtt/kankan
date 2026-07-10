# ============================================================
# 这个文件是干什么的：第十一份改库图纸——新增「内容类型」轴。
#   1) 建 content_type 枚举（ai_image/ai_video/web/app/tool/opensource/prompt）
#   2) projects 加 content_type 列（可空），从 category 尽力回填 + 建索引
#   3) users 加 interest_content_types 列（text[] + CHECK），给「看看」兴趣设置用
# 它对应产品里的什么功能：前端「看看」的成果类型筛选/兴趣，终于在后端有真归属。
#   与现有 category（用途）、domains/interests（职业）正交，两套都保留不删。
# 如果它出错了：迁移失败服务起不来（正常则无感，前端筛选/兴趣接真后才用到）。
# ============================================================
"""add content_type axis: projects.content_type + users.interest_content_types

Revision ID: 0011_content_type
Revises: 0010_fk_indexes
Create Date: 2026-07-10 00:00:00

"""
from typing import Sequence, Union

from alembic import op

revision: str = "0011_content_type"
down_revision: Union[str, None] = "0010_fk_indexes"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_CONTENT_TYPES = ("ai_image", "ai_video", "web", "app", "tool", "opensource", "prompt")
_VALS = ", ".join(f"'{v}'" for v in _CONTENT_TYPES)


def upgrade() -> None:
    # 1) 内容类型枚举
    op.execute(f'CREATE TYPE "content_type" AS ENUM ({_VALS})')

    # 2) projects.content_type（可空，与 category/domains 正交）
    op.execute('ALTER TABLE projects ADD COLUMN content_type "content_type"')
    # 3) 从 category 尽力回填（用途→成果类型；映射不到的落 tool，新项目由发布/AI 管线显式填）
    op.execute(
        """
        UPDATE projects SET content_type = (CASE category
            WHEN 'image_design' THEN 'ai_image'
            WHEN 'video_music'  THEN 'ai_video'
            WHEN 'ai_apps'      THEN 'app'
            ELSE 'tool'
        END)::"content_type"
        """
    )
    op.create_index("ix_projects_content_type_status", "projects", ["content_type", "status"])

    # 4) users.interest_content_types（多选，CHECK 限定取值）
    op.execute("ALTER TABLE users ADD COLUMN interest_content_types text[] NOT NULL DEFAULT '{}'::text[]")
    op.execute(
        f"ALTER TABLE users ADD CONSTRAINT interest_content_types_allowed "
        f"CHECK (interest_content_types <@ ARRAY[{_VALS}]::text[])"
    )


def downgrade() -> None:
    op.execute("ALTER TABLE users DROP CONSTRAINT IF EXISTS interest_content_types_allowed")
    op.execute("ALTER TABLE users DROP COLUMN IF EXISTS interest_content_types")
    op.drop_index("ix_projects_content_type_status", table_name="projects")
    op.execute("ALTER TABLE projects DROP COLUMN IF EXISTS content_type")
    op.execute('DROP TYPE IF EXISTS "content_type"')
