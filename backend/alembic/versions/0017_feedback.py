"""feedback table (bug / suggestion)

Revision ID: 0017_feedback
Revises: 0016_candidate_content_kind
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "0017_feedback"
down_revision: Union[str, None] = "0016_candidate_content_kind"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "feedbacks",
        sa.Column("id", sa.dialects.postgresql.UUID(as_uuid=True), primary_key=True,
                  server_default=sa.text("gen_random_uuid()")),
        sa.Column("user_id", sa.dialects.postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True),
        sa.Column("category", sa.String(length=20), nullable=False, server_default="bug"),
        sa.Column("content", sa.Text(), nullable=False),
        sa.Column("contact", sa.String(length=100), nullable=True),
        sa.Column("app_version", sa.String(length=40), nullable=True),
        sa.Column("platform", sa.String(length=20), nullable=True),
        sa.Column("device_info", sa.String(length=200), nullable=True),
        sa.Column("status", sa.String(length=20), nullable=False, server_default="new"),
        sa.Column("handled_by_user_id", sa.dialects.postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True),
        sa.Column("handled_at", sa.dialects.postgresql.TIMESTAMP(timezone=True), nullable=True),
        sa.Column("admin_note", sa.Text(), nullable=True),
        sa.Column("created_at", sa.dialects.postgresql.TIMESTAMP(timezone=True),
                  nullable=False, server_default=sa.text("now()")),
        sa.Column("updated_at", sa.dialects.postgresql.TIMESTAMP(timezone=True),
                  nullable=False, server_default=sa.text("now()")),
        sa.CheckConstraint("category IN ('bug','suggestion','other')", name="ck_feedback_category"),
        sa.CheckConstraint("status IN ('new','handled')", name="ck_feedback_status"),
    )
    op.create_index("ix_feedbacks_status_created_at", "feedbacks", ["status", "created_at"])


def downgrade() -> None:
    op.drop_index("ix_feedbacks_status_created_at", table_name="feedbacks")
    op.drop_table("feedbacks")
