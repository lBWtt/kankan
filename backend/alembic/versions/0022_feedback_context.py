"""add feedback context fields

revision: 0022_feedback_context
"""
from alembic import op
import sqlalchemy as sa


revision = "0022_feedback_context"
down_revision = "0021_admin_action_post_target"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("feedbacks", sa.Column("source_page", sa.String(length=120), nullable=True))
    op.add_column("feedbacks", sa.Column("error_code", sa.String(length=80), nullable=True))


def downgrade() -> None:
    op.drop_column("feedbacks", "error_code")
    op.drop_column("feedbacks", "source_page")
