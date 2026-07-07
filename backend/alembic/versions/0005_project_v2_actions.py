# ============================================================
# 这个文件是干什么的：第五份改库图纸，给新版项目页补动作按钮和点击流水。
# 它对应产品里的什么功能：Flutter 详情页的拿走、去看看、看怎么做，以及拿走成功计数。
# 如果它出错了，用户会看到什么现象：迁移失败，或者新版项目发不出来、按钮点了不留痕。
# ============================================================
"""project v2 actions

Revision ID: 0005
Revises: 0004
Create Date: 2026-06-30

"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "0005"
down_revision: Union[str, None] = "0004"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("projects", sa.Column("intro", sa.Text(), nullable=True))
    op.add_column("projects", sa.Column("vertical", sa.String(length=50), nullable=True))
    op.add_column(
        "projects",
        sa.Column("takeaway_count", sa.Integer(), server_default=sa.text("0"), nullable=False),
    )
    op.add_column("projects", sa.Column("repo_stars", sa.String(length=20), nullable=True))

    op.create_table(
        "project_actions",
        sa.Column("id", postgresql.UUID(as_uuid=True), server_default=sa.text("gen_random_uuid()"), nullable=False),
        sa.Column("project_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("action_type", sa.String(length=20), nullable=False),
        sa.Column("action_sub", sa.String(length=20), nullable=False),
        sa.Column("label", sa.String(length=255), nullable=False),
        sa.Column("sublabel", sa.String(length=255), nullable=True),
        sa.Column("content", sa.Text(), nullable=True),
        sa.Column("file_media_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("file_name", sa.String(length=255), nullable=True),
        sa.Column("file_size_bytes", sa.Integer(), nullable=True),
        sa.Column("url", sa.Text(), nullable=True),
        sa.Column("sort_order", sa.Integer(), server_default=sa.text("0"), nullable=False),
        sa.Column("created_at", postgresql.TIMESTAMP(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.CheckConstraint("action_type IN ('take', 'go', 'how')", name="project_action_type_allowed"),
        sa.CheckConstraint(
            "action_sub IN ('text', 'file', 'github', 'appstore', 'url', 'workflow')",
            name="project_action_sub_allowed",
        ),
        sa.ForeignKeyConstraint(["file_media_id"], ["project_media.id"], name="fk_project_actions_file_media_id_project_media"),
        sa.ForeignKeyConstraint(["project_id"], ["projects.id"], name="fk_project_actions_project_id_projects"),
        sa.PrimaryKeyConstraint("id", name="pk_project_actions"),
    )
    op.create_index("ix_project_actions_project_id", "project_actions", ["project_id"])
    op.create_index("ix_project_actions_file_media_id", "project_actions", ["file_media_id"])

    op.create_table(
        "project_action_events",
        sa.Column("id", postgresql.UUID(as_uuid=True), server_default=sa.text("gen_random_uuid()"), nullable=False),
        sa.Column("project_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("action_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("anon_client_id", sa.String(length=64), nullable=True),
        sa.Column("event_type", sa.String(length=20), nullable=False),
        sa.Column("created_at", postgresql.TIMESTAMP(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.CheckConstraint("event_type IN ('click', 'success')", name="project_action_event_type_allowed"),
        sa.CheckConstraint(
            "user_id IS NOT NULL OR anon_client_id IS NOT NULL",
            name="project_action_event_has_actor",
        ),
        sa.ForeignKeyConstraint(["action_id"], ["project_actions.id"], name="fk_project_action_events_action_id_project_actions"),
        sa.ForeignKeyConstraint(["project_id"], ["projects.id"], name="fk_project_action_events_project_id_projects"),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], name="fk_project_action_events_user_id_users"),
        sa.PrimaryKeyConstraint("id", name="pk_project_action_events"),
    )
    op.create_index(
        "ix_project_action_events_project_created",
        "project_action_events",
        ["project_id", "created_at"],
    )
    op.create_index(
        "ix_project_action_events_action_created",
        "project_action_events",
        ["action_id", "created_at"],
    )
    op.create_index(
        "ix_project_action_events_user_created",
        "project_action_events",
        ["user_id", "created_at"],
    )
    op.create_index(
        "ix_project_action_events_anon_created",
        "project_action_events",
        ["anon_client_id", "created_at"],
    )


def downgrade() -> None:
    op.drop_index("ix_project_action_events_anon_created", table_name="project_action_events")
    op.drop_index("ix_project_action_events_user_created", table_name="project_action_events")
    op.drop_index("ix_project_action_events_action_created", table_name="project_action_events")
    op.drop_index("ix_project_action_events_project_created", table_name="project_action_events")
    op.drop_table("project_action_events")

    op.drop_index("ix_project_actions_file_media_id", table_name="project_actions")
    op.drop_index("ix_project_actions_project_id", table_name="project_actions")
    op.drop_table("project_actions")

    op.drop_column("projects", "repo_stars")
    op.drop_column("projects", "takeaway_count")
    op.drop_column("projects", "vertical")
    op.drop_column("projects", "intro")
