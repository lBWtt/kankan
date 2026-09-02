"""content constitution v1.1 fields

Revision ID: 0023_content_constitution_v11
Revises: 0022_feedback_context
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql


revision: str = "0023_content_constitution_v11"
down_revision: Union[str, None] = "0022_feedback_context"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


_SHARED_COLUMNS = (
    sa.Column("work_form", sa.String(length=30), nullable=True),
    sa.Column("creator_type", sa.String(length=20), nullable=True),
    sa.Column("access_friction", sa.String(length=20), nullable=True),
    sa.Column("experience_type", sa.String(length=30), nullable=True),
    sa.Column("experience_url", sa.Text(), nullable=True),
    sa.Column("experience_content", sa.Text(), nullable=True),
    sa.Column("hook_clarity", sa.Integer(), nullable=True),
    sa.Column("visual_impact", sa.Integer(), nullable=True),
    sa.Column("surprise", sa.Integer(), nullable=True),
    sa.Column("tryability", sa.Integer(), nullable=True),
    sa.Column("shareability", sa.Integer(), nullable=True),
    sa.Column("attraction_score", sa.Integer(), nullable=True),
    sa.Column("value_score", sa.Integer(), nullable=True),
    sa.Column("is_strong_visual", sa.Boolean(), nullable=False, server_default=sa.text("false")),
    sa.Column("is_direct_tryable", sa.Boolean(), nullable=False, server_default=sa.text("false")),
    sa.Column("selected_proof_media", postgresql.JSONB(astext_type=sa.Text()), nullable=True),
    sa.Column("title_candidates", postgresql.JSONB(astext_type=sa.Text()), nullable=True),
    sa.Column("policy_version", sa.String(length=20), nullable=False, server_default="1.1"),
    sa.Column("score_version", sa.String(length=60), nullable=True),
    sa.Column("ai_analysis_json", postgresql.JSONB(astext_type=sa.Text()), nullable=True),
    sa.Column("human_override_json", postgresql.JSONB(astext_type=sa.Text()), nullable=True),
    sa.Column("override_reason", sa.Text(), nullable=True),
)


def _add_shared(table: str) -> None:
    for column in _SHARED_COLUMNS:
        op.add_column(table, column.copy())
    op.create_check_constraint(
        f"{table}_work_form_allowed", table,
        "work_form IS NULL OR work_form IN ('app','website','workflow','model','prompt','ai_art','game','tool')",
    )
    op.create_check_constraint(
        f"{table}_creator_type_allowed", table,
        "creator_type IS NULL OR creator_type IN ('indie','company')",
    )
    op.create_check_constraint(
        f"{table}_access_friction_allowed", table,
        "access_friction IS NULL OR access_friction IN ('instant','install','technical')",
    )
    op.create_check_constraint(
        f"{table}_experience_type_allowed", table,
        "experience_type IS NULL OR experience_type IN ('web','video','gallery','download','model_page','workflow_file','prompt_content','game')",
    )
    for field in ("hook_clarity", "visual_impact", "surprise", "tryability", "shareability", "attraction_score", "value_score"):
        op.create_check_constraint(
            f"{table}_{field}_range", table,
            f"{field} IS NULL OR ({field} >= 0 AND {field} <= 100)",
        )


def upgrade() -> None:
    _add_shared("candidate_contents")
    op.add_column("candidate_contents", sa.Column("is_work", sa.Boolean(), nullable=True))
    op.add_column("candidate_contents", sa.Column("work_rejection_reason", sa.Text(), nullable=True))
    _add_shared("projects")
    op.create_index("ix_projects_slate_quality", "projects", ["status", "attraction_score", "published_at"])


def _drop_shared(table: str) -> None:
    for field in ("hook_clarity", "visual_impact", "surprise", "tryability", "shareability", "attraction_score", "value_score"):
        op.drop_constraint(f"{table}_{field}_range", table, type_="check")
    op.drop_constraint(f"{table}_experience_type_allowed", table, type_="check")
    op.drop_constraint(f"{table}_access_friction_allowed", table, type_="check")
    op.drop_constraint(f"{table}_creator_type_allowed", table, type_="check")
    op.drop_constraint(f"{table}_work_form_allowed", table, type_="check")
    for name in reversed([column.name for column in _SHARED_COLUMNS]):
        op.drop_column(table, name)


def downgrade() -> None:
    op.drop_index("ix_projects_slate_quality", table_name="projects")
    _drop_shared("projects")
    op.drop_column("candidate_contents", "work_rejection_reason")
    op.drop_column("candidate_contents", "is_work")
    _drop_shared("candidate_contents")
