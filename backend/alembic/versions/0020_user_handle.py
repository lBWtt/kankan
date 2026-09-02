"""add user handle (stable @username)

Revision ID: 0020_user_handle
Revises: 0019_candidate_try_url
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "0020_user_handle"
down_revision: Union[str, None] = "0019_candidate_try_url"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # 1) 先加可空列（不阻塞存量行）。
    op.add_column("users", sa.Column("handle", sa.String(length=30), nullable=True))
    # 2) 回填存量用户：u + 用户 UUID 前 8 位十六进制（字母开头、唯一性极高，与 core/handle 一致）。
    op.execute(
        "UPDATE users SET handle = 'u' || substr(replace(id::text, '-', ''), 1, 8) "
        "WHERE handle IS NULL"
    )
    # 3) 唯一约束：handle 全局唯一（大小写不敏感靠应用层统一存小写）。
    op.create_unique_constraint("uq_users_handle", "users", ["handle"])


def downgrade() -> None:
    op.drop_constraint("uq_users_handle", "users", type_="unique")
    op.drop_column("users", "handle")
