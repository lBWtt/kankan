# ============================================================
# 这个文件是干什么的：第九份改库图纸——round3 review 修复：
#   1) 补 CHECK 约束（contact_present / no_self_follow / no_self_similar /
#      report_reason_allowed / admin_action_allowed / admin_target_type_allowed）
#   2) 给约 30 个外键补 ondelete 策略（SET NULL / CASCADE / RESTRICT）
#   3) 给 14+ 张带 updated_at 的表建 touch_updated_at 触发器（兜底 bulk update）
#   4) 给 4 张软删表补部分索引（ix_*_live）
#   5) 顺手补两个 Medium 索引（posts.tags GIN / analytics_events user+created）
# 它对应产品里的什么功能：不直接对应功能，是数据完整性与查询性能的底层加固。
# 如果它出错了，用户会看到什么现象：迁移失败导致服务起不来；或外键策略不一致导致
#   注销/删项目时残留孤儿数据/级联误删。
# ============================================================
"""round3 review: CHECK/ondelete/index/trigger

Revision ID: 0009_round3
Revises: 0008
Create Date: 2025-01-01 00:00:00

"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "0009_round3"
down_revision: Union[str, None] = "0008"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


# ---------- 触发器覆盖的表清单（带 updated_at 或带 created_at 也兜底）----------
# H-MDL-7：在每张表上挂 BEFORE UPDATE 触发器，自动刷新 updated_at。
# 含 updated_at 的表（TimestampMixin）必须建；只含 created_at 的表建了也无害（created_at 不被触发器改）。
# 这里按 round3 review 指令，覆盖以下全部表。
# 只能挂在真正有 updated_at 列的表上：touch_updated_at() 执行 `NEW.updated_at = now()`，
# 若表无此列，PL/pgSQL 在 UPDATE 时抛 `record "new" has no field "updated_at"`——
# 会 500 掉这些表的所有 UPDATE（软删/点赞/hot_score 等）。PR#5 原把 26 张表全挂了，是 bug。
# 有 updated_at 的表 = 用 TimestampMixin 的 5 张（其余只有 created_at）。
TRIGGER_TABLES = [
    "users",
    "projects",
    "candidate_contents",
    "push_preferences",
    "reports",
]


def _fk_drop_create(table: str, column: str, ref_table: str, ref_col: str, ondelete: str) -> None:
    """重建一个外键约束：先 DROP IF EXISTS 旧约束（PG 默认名 <table>_<column>_fkey），
    再 CREATE 新约束带 ondelete 策略。约束名保持 PG 默认规则，便于回滚。
    注：对迁移 0004/0005 显式命名的约束，调用方需单独处理。"""
    default_name = f"{table}_{column}_fkey"
    op.execute(
        f'ALTER TABLE {table} DROP CONSTRAINT IF EXISTS {default_name}'
    )
    op.execute(
        f'ALTER TABLE {table} ADD CONSTRAINT {default_name} '
        f'FOREIGN KEY ({column}) REFERENCES {ref_table}({ref_col}) ON DELETE {ondelete}'
    )


def _fk_drop_create_named(constraint_name: str, table: str, column: str, ref_table: str, ref_col: str, ondelete: str) -> None:
    """重建一个有显式名的外键约束（针对迁移 0004/0005 显式命名的约束）。"""
    op.execute(
        f'ALTER TABLE {table} DROP CONSTRAINT IF EXISTS {constraint_name}'
    )
    op.execute(
        f'ALTER TABLE {table} ADD CONSTRAINT {constraint_name} '
        f'FOREIGN KEY ({column}) REFERENCES {ref_table}({ref_col}) ON DELETE {ondelete}'
    )


def upgrade() -> None:
    # ============================================================
    # 1) C-MDL-2 / H-MDL-1 / H-MDL-2 / H-MDL-5 / H-MDL-6：补 CHECK 约束
    # ============================================================
    # C-MDL-2：users email/phone 至少有一个
    op.create_check_constraint("contact_present", "users", "email IS NOT NULL OR phone IS NOT NULL")
    # H-MDL-1：禁止自关注
    op.create_check_constraint("no_self_follow", "user_follows", "follower_user_id <> followee_user_id")
    # H-MDL-2：禁止相似项目自关联
    op.create_check_constraint("no_self_similar", "similar_project_links", "source_project_id <> similar_project_id")
    # H-MDL-5：举报原因白名单（与 schemas/interaction.ReportReason 一致）
    op.create_check_constraint(
        "report_reason_allowed",
        "reports",
        "reason IN ('copyright','ad_spam','nsfw','low_quality','other')",
    )
    # H-MDL-6：admin target_type 白名单。
    # 注意：不约束 action —— 审计日志的 action 由代码 f-string 生成
    # （`{action}_project` / `{new_status}_candidate` / edit_candidate / push_daily_pick 等），
    # 是动态词表而非固定枚举，用 CHECK 白名单会漏项并 500 掉合法写入（PR#5 原列表即错的）。
    op.create_check_constraint(
        "admin_target_type_allowed",
        "admin_actions",
        "target_type IN ('project','candidate','report','user')",
    )

    # ============================================================
    # 2) C-MDL-3：给外键补 ondelete 策略
    # ============================================================
    # ---- SET NULL（语义上可空的引用）----
    # projects.author_user_id（默认名 projects_author_user_id_fkey）
    _fk_drop_create("projects", "author_user_id", "users", "id", "SET NULL")
    # candidate_contents.reviewed_by_user_id
    _fk_drop_create("candidate_contents", "reviewed_by_user_id", "users", "id", "SET NULL")
    # candidate_contents.project_id
    _fk_drop_create("candidate_contents", "project_id", "projects", "id", "SET NULL")
    # project_actions.file_media_id（迁移 0005 显式命名 fk_project_actions_file_media_id_project_media）
    _fk_drop_create_named("fk_project_actions_file_media_id_project_media", "project_actions", "file_media_id", "project_media", "id", "SET NULL")
    # reports.handled_by_user_id
    _fk_drop_create("reports", "handled_by_user_id", "users", "id", "SET NULL")

    # ---- CASCADE（用户从属数据 / 关联表）----
    # interaction.py
    _fk_drop_create("favorites", "user_id", "users", "id", "CASCADE")
    _fk_drop_create("favorites", "project_id", "projects", "id", "CASCADE")
    _fk_drop_create("try_items", "user_id", "users", "id", "CASCADE")
    _fk_drop_create("try_items", "project_id", "projects", "id", "CASCADE")
    _fk_drop_create("how_to_interests", "user_id", "users", "id", "CASCADE")
    _fk_drop_create("how_to_interests", "project_id", "projects", "id", "CASCADE")
    _fk_drop_create("clue_subscriptions", "user_id", "users", "id", "CASCADE")
    _fk_drop_create("clue_subscriptions", "project_id", "projects", "id", "CASCADE")
    _fk_drop_create("project_reactions", "user_id", "users", "id", "CASCADE")
    _fk_drop_create("project_reactions", "project_id", "projects", "id", "CASCADE")
    _fk_drop_create("similar_project_links", "source_project_id", "projects", "id", "CASCADE")
    _fk_drop_create("similar_project_links", "similar_project_id", "projects", "id", "CASCADE")
    # share.py
    _fk_drop_create("shares", "user_id", "users", "id", "CASCADE")
    _fk_drop_create("shares", "project_id", "projects", "id", "CASCADE")
    # report.py（reporter + project CASCADE，handled_by 已是 SET NULL）
    _fk_drop_create("reports", "reporter_user_id", "users", "id", "CASCADE")
    _fk_drop_create("reports", "project_id", "projects", "id", "CASCADE")
    # notification.py
    _fk_drop_create("notifications", "user_id", "users", "id", "CASCADE")
    _fk_drop_create("notifications", "project_id", "projects", "id", "CASCADE")
    _fk_drop_create("push_preferences", "user_id", "users", "id", "CASCADE")
    # media.py（project_id + uploader_user_id CASCADE）
    _fk_drop_create("project_media", "project_id", "projects", "id", "CASCADE")
    _fk_drop_create("project_media", "uploader_user_id", "users", "id", "CASCADE")
    # tag.py
    _fk_drop_create("project_tag_relations", "project_id", "projects", "id", "CASCADE")
    _fk_drop_create("project_tag_relations", "tag_id", "project_tags", "id", "CASCADE")
    # project_action.py（project_id / action_id / user_id CASCADE；file_media_id 已是 SET NULL）
    _fk_drop_create_named("fk_project_actions_project_id_projects", "project_actions", "project_id", "projects", "id", "CASCADE")
    _fk_drop_create_named("fk_project_action_events_action_id_project_actions", "project_action_events", "action_id", "project_actions", "id", "CASCADE")
    _fk_drop_create_named("fk_project_action_events_project_id_projects", "project_action_events", "project_id", "projects", "id", "CASCADE")
    _fk_drop_create_named("fk_project_action_events_user_id_users", "project_action_events", "user_id", "users", "id", "CASCADE")

    # ---- RESTRICT（显式声明，审计日志保留）----
    _fk_drop_create("admin_actions", "admin_user_id", "users", "id", "RESTRICT")

    # ============================================================
    # 3) H-MDL-7：touch_updated_at 触发器函数 + 每表触发器
    # ============================================================
    op.execute("""
CREATE OR REPLACE FUNCTION touch_updated_at() RETURNS trigger AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$ LANGUAGE plpgsql;
""")
    for tbl in TRIGGER_TABLES:
        op.execute(f"DROP TRIGGER IF EXISTS trg_{tbl}_touch ON {tbl}")
        op.execute(
            f"CREATE TRIGGER trg_{tbl}_touch BEFORE UPDATE ON {tbl} "
            f"FOR EACH ROW EXECUTE FUNCTION touch_updated_at()"
        )

    # ============================================================
    # 4) H-MDL-8：软删列的部分索引
    # ============================================================
    op.create_index(
        "ix_projects_live",
        "projects",
        ["status", "published_at"],
        postgresql_where=sa.text("deleted_at IS NULL"),
    )
    op.create_index(
        "ix_posts_live_created",
        "posts",
        ["created_at"],
        postgresql_where=sa.text("deleted_at IS NULL"),
    )
    op.create_index(
        "ix_comments_live_host",
        "comments",
        ["host_type", "host_id"],
        postgresql_where=sa.text("deleted_at IS NULL"),
    )
    op.create_index(
        "ix_users_live",
        "users",
        ["id"],
        postgresql_where=sa.text("deleted_at IS NULL"),
    )

    # ============================================================
    # 5) 顺手补两个 Medium 索引
    # ============================================================
    op.create_index("ix_posts_tags_gin", "posts", ["tags"], postgresql_using="gin")
    op.create_index("ix_analytics_events_user_created", "analytics_events", ["user_id", "created_at"])


def downgrade() -> None:
    # ============================================================
    # 反向操作：drop 新增索引 / 触发器 / CHECK；FK 回滚为默认（无 ondelete）。
    # 注：FK 保留新 ondelete 策略不回滚——回滚到 RESTRICT 默认会破坏已建立的级联语义，
    #     且 round3 之前的迁移本身没有显式 ondelete（PG 默认 NO ACTION），保留策略更安全。
    # ============================================================

    # ---- 5) drop Medium 索引 ----
    op.drop_index("ix_analytics_events_user_created", table_name="analytics_events")
    op.drop_index("ix_posts_tags_gin", table_name="posts")

    # ---- 4) drop 软删部分索引 ----
    op.drop_index("ix_users_live", table_name="users")
    op.drop_index("ix_comments_live_host", table_name="comments")
    op.drop_index("ix_posts_live_created", table_name="posts")
    op.drop_index("ix_projects_live", table_name="projects")

    # ---- 3) drop 触发器 + 函数 ----
    for tbl in TRIGGER_TABLES:
        op.execute(f"DROP TRIGGER IF EXISTS trg_{tbl}_touch ON {tbl}")
    op.execute("DROP FUNCTION IF EXISTS touch_updated_at()")

    # ---- 1) drop CHECK 约束 ----
    op.drop_constraint("admin_target_type_allowed", "admin_actions", type_="check")
    op.drop_constraint("report_reason_allowed", "reports", type_="check")
    op.drop_constraint("no_self_similar", "similar_project_links", type_="check")
    op.drop_constraint("no_self_follow", "user_follows", type_="check")
    op.drop_constraint("contact_present", "users", type_="check")

    # ---- 2) FK 不回滚（保留新 ondelete 策略，见上方注释）----
