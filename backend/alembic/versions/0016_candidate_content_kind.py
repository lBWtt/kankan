"""candidate content_kind (project vs post/动态)

Revision ID: 0016_candidate_content_kind
Revises: 0015_user_school_age
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "0016_candidate_content_kind"
down_revision: Union[str, None] = "0015_user_school_age"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # 候选走哪条落地路径：project=复制成正式项目（默认，兼容存量）；post=改写成马甲发的动态。
    op.add_column(
        "candidate_contents",
        sa.Column("content_kind", sa.String(length=20), nullable=False, server_default="project"),
    )
    op.create_check_constraint(
        "ck_candidate_contents_content_kind",
        "candidate_contents",
        "content_kind IN ('project', 'post')",
    )


def downgrade() -> None:
    op.drop_constraint("ck_candidate_contents_content_kind", "candidate_contents", type_="check")
    op.drop_column("candidate_contents", "content_kind")
