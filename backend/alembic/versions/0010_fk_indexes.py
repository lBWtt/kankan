# ============================================================
# 这个文件是干什么的：第十份改库图纸——给两个外键列补索引。
#   posts.quote_project_id（部分索引，IS NOT NULL）、comments.author_user_id。
# 它对应产品里的什么功能：不直接对应功能，是查询/删除性能的底层加固。
# 如果它出错了，用户会看到什么现象：迁移失败服务起不来（正常则无感，只是删项目/注销更快）。
#
# 背景：这两列都带 ON DELETE 动作（quote_project_id=SET NULL，author_user_id=CASCADE）。
#   被引用行删除时，PG 需回扫引用表找出受影响行；无索引会退化成全表顺扫。
#   补索引后：删项目/注销用户更快，也支撑「引用某项目的动态」「某用户的评论」查询。
# ============================================================
"""add indexes on FK columns posts.quote_project_id / comments.author_user_id

Revision ID: 0010_fk_indexes
Revises: 0009_round3
Create Date: 2026-07-10 00:00:00

"""
from typing import Sequence, Union

from alembic import op
from sqlalchemy import text

revision: str = "0010_fk_indexes"
down_revision: Union[str, None] = "0009_round3"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # 大多数动态不引用项目 → IS NOT NULL 部分索引，省空间且覆盖 FK 回扫（查的都是非 NULL 值）。
    op.create_index(
        "ix_posts_quote_project",
        "posts",
        ["quote_project_id"],
        postgresql_where=text("quote_project_id IS NOT NULL"),
    )
    # author_user_id 为 NOT NULL，普通索引即可。
    op.create_index("ix_comments_author", "comments", ["author_user_id"])


def downgrade() -> None:
    op.drop_index("ix_comments_author", table_name="comments")
    op.drop_index("ix_posts_quote_project", table_name="posts")
