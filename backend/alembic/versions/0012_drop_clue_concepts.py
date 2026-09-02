# ============================================================
# 这个文件是干什么的：第十二份改库图纸——清掉旧"实现线索/复现"概念的库结构。
#   1) 删 clue_subscriptions 表（"订阅线索更新"功能已废，0 行，安全）
#   2) 删 push_preferences.clue_update_enabled 列
#   3) 重建 notification_type 枚举：how_to_interest → want_to_try（改名），去掉 clue_update
# 它对应产品里的什么功能：定位从"想看怎么做/复现"转向"想试/去用"后的后端收口。
# 如果它出错了：迁移失败服务起不来（本迁移在 notifications/clue_subscriptions 均 0 行时无风险）。
# ============================================================
"""drop clue_subscriptions + clue_update; rename notification type how_to_interest->want_to_try

Revision ID: 0012_drop_clue_concepts
Revises: 0011_content_type
Create Date: 2026-07-13 00:00:00

"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "0012_drop_clue_concepts"
down_revision: Union[str, None] = "0011_content_type"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_NEW_TYPES = (
    "daily_pick", "weekly_ranking", "want_to_try",
    "similar_project", "content_status", "system", "interaction",
)
_OLD_TYPES = (
    "daily_pick", "weekly_ranking", "how_to_interest", "clue_update",
    "similar_project", "content_status", "system", "interaction",
)


def _recreate_enum(new_vals: tuple, map_sql: str) -> None:
    """把 notification_type 枚举换成 new_vals；notifications.type 用 map_sql 转换。"""
    vals = ", ".join(f"'{v}'" for v in new_vals)
    op.execute("ALTER TYPE notification_type RENAME TO notification_type_tmp")
    op.execute(f"CREATE TYPE notification_type AS ENUM ({vals})")
    op.execute(
        f"ALTER TABLE notifications ALTER COLUMN type TYPE notification_type USING {map_sql}"
    )
    op.execute("DROP TYPE notification_type_tmp")


def upgrade() -> None:
    op.drop_table("clue_subscriptions")
    op.drop_column("push_preferences", "clue_update_enabled")
    # how_to_interest → want_to_try（clue_update 无行可留；0 行时纯 no-op）
    _recreate_enum(
        _NEW_TYPES,
        "(CASE WHEN type::text = 'how_to_interest' THEN 'want_to_try' "
        "ELSE type::text END)::notification_type",
    )


def downgrade() -> None:
    _recreate_enum(
        _OLD_TYPES,
        "(CASE WHEN type::text = 'want_to_try' THEN 'how_to_interest' "
        "ELSE type::text END)::notification_type",
    )
    op.add_column(
        "push_preferences",
        sa.Column("clue_update_enabled", sa.Boolean(), nullable=False,
                  server_default=sa.text("true")),
    )
    op.create_table(
        "clue_subscriptions",
        sa.Column("id", sa.dialects.postgresql.UUID(as_uuid=True),
                  server_default=sa.text("gen_random_uuid()"), primary_key=True),
        sa.Column("user_id", sa.dialects.postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("project_id", sa.dialects.postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("created_at", sa.TIMESTAMP(timezone=True),
                  server_default=sa.text("now()"), nullable=False),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["project_id"], ["projects.id"], ondelete="CASCADE"),
        sa.UniqueConstraint("user_id", "project_id",
                            name="uq_clue_subscriptions_user_project"),
    )
    op.create_index("ix_clue_subscriptions_project_id", "clue_subscriptions", ["project_id"])
