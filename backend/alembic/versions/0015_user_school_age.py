"""add user school and age

Revision ID: 0015_user_school_age
Revises: 0014_topic_follows
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "0015_user_school_age"
down_revision: Union[str, None] = "0014_topic_follows"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("users", sa.Column("school", sa.String(length=100), nullable=True))
    op.add_column("users", sa.Column("age", sa.Integer(), nullable=True))
    op.create_check_constraint("ck_users_age_valid", "users", "age IS NULL OR age BETWEEN 1 AND 120")


def downgrade() -> None:
    op.drop_constraint("ck_users_age_valid", "users", type_="check")
    op.drop_column("users", "age")
    op.drop_column("users", "school")
