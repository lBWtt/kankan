# ============================================================
# 这个文件是干什么的：第一份"建库图纸"——一次性创建全部 10 个枚举、18 张表
#   和所有索引/约束，严格按字段·API v1.3 §3/§4/§11 与 PRD v1.3 §8.4。
# 它对应产品里的什么功能：所有功能的数据底座；执行它（alembic upgrade head）数据库才存在。
# 如果它出错了，用户会看到什么现象：数据库根本建不起来，后端无法上线，App 无任何内容。
# ============================================================
"""initial schema: 10 enums + 18 tables + indexes (per 字段·API v1.3 / PRD v1.3 §8.4)

Revision ID: 0001
Revises:
Create Date: 2026-06-10

"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "0001"
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

# ---------- 枚举值定义（与 app/models/enums.py 一字不差） ----------
PROJECT_STATUS = ("draft", "published", "hidden", "under_review", "rejected", "taken_down", "deleted")
CANDIDATE_STATUS = ("ai_collected", "ai_processed", "pending_review", "edited", "approved", "parked", "discarded")
CATEGORY = (
    "fun_ideas", "image_design", "video_music", "life_utility", "work_efficiency", "learning_growth",
    "business_ideas", "automation_tools", "creator_tools", "ai_apps", "weird_fun", "future_cases",
)
CONTENT_SOURCE_TYPE = ("ai_crawled", "manual_import", "user_original", "user_discovery")
REACTION_TYPE = ("creative", "big_brain", "cool")
SHARE_STATUS = ("clicked", "completed")
SHARE_CHANNEL = ("wechat", "moments", "x", "xiaohongshu", "copy_link", "other")
NOTIFICATION_TYPE = (
    "daily_pick", "weekly_ranking", "how_to_interest", "clue_update",
    "similar_project", "content_status", "system", "interaction",
)
REPORT_STATUS = ("pending", "processing", "resolved", "rejected")
LANGUAGE = ("zh-CN", "en-US")
DOMAIN = ("dev", "design", "video", "marketing", "writing", "education", "ecommerce", "office", "cad_3d", "other")
AI_BADGE = ("worth_a_look", "high_potential", "staff_pick", "none")

ENUM_TYPES = {
    "project_status": PROJECT_STATUS,
    "candidate_status": CANDIDATE_STATUS,
    "category": CATEGORY,
    "content_source_type": CONTENT_SOURCE_TYPE,
    "reaction_type": REACTION_TYPE,
    "share_status": SHARE_STATUS,
    "share_channel": SHARE_CHANNEL,
    "notification_type": NOTIFICATION_TYPE,
    "report_status": REPORT_STATUS,
    "language": LANGUAGE,
}


def _enum(name: str) -> postgresql.ENUM:
    """引用已创建的枚举类型（类型本体在 upgrade 开头统一 CREATE TYPE）。"""
    return postgresql.ENUM(*ENUM_TYPES[name], name=name, create_type=False)


def _quoted(values) -> str:
    return ", ".join(f"'{v}'" for v in values)


def _uuid_pk() -> sa.Column:
    return sa.Column(
        "id", postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")
    )


def _created_at() -> sa.Column:
    return sa.Column("created_at", postgresql.TIMESTAMP(timezone=True), server_default=sa.func.now(), nullable=False)


def _updated_at() -> sa.Column:
    return sa.Column("updated_at", postgresql.TIMESTAMP(timezone=True), server_default=sa.func.now(), nullable=False)


def upgrade() -> None:
    # ---------- 1. 枚举类型 ----------
    for name, values in ENUM_TYPES.items():
        op.execute(f'CREATE TYPE "{name}" AS ENUM ({_quoted(values)})')

    # ---------- 2. users 用户 ----------
    op.create_table(
        "users",
        _uuid_pk(),
        sa.Column("email", sa.String(255)),
        sa.Column("phone", sa.String(20)),
        sa.Column("nickname", sa.String(50)),
        sa.Column("avatar_url", sa.Text()),
        sa.Column("bio", sa.String(500)),
        sa.Column("language_preference", _enum("language"), nullable=False, server_default="zh-CN"),
        sa.Column("country_region", sa.String(50)),
        sa.Column("interests", postgresql.ARRAY(sa.Text()), nullable=False, server_default=sa.text("'{}'::text[]")),
        sa.Column("role", sa.String(20)),
        sa.Column("is_admin", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column("membership_tier", sa.String(20)),
        sa.Column("membership_expires_at", postgresql.TIMESTAMP(timezone=True)),
        _created_at(),
        _updated_at(),
        sa.Column("deleted_at", postgresql.TIMESTAMP(timezone=True)),
        sa.UniqueConstraint("email", name="uq_users_email"),
        sa.UniqueConstraint("phone", name="uq_users_phone"),
        # 注意：CHECK 约束只写"裸名"，env.py 的命名规则会自动加 ck_<表名>_ 前缀
        sa.CheckConstraint(f"role IS NULL OR role IN ({_quoted(('creator', 'developer', 'general'))})", name="role_allowed"),
        sa.CheckConstraint(f"interests <@ ARRAY[{_quoted(DOMAIN)}]::text[]", name="interests_allowed"),
    )

    # ---------- 3. projects 项目（核心表） ----------
    op.create_table(
        "projects",
        _uuid_pk(),
        sa.Column("author_user_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id")),
        sa.Column("title", sa.String(80), nullable=False),
        sa.Column("tagline", sa.String(140), nullable=False),
        sa.Column("summary", sa.String(500), nullable=False),
        sa.Column("description", sa.Text()),
        sa.Column("category", _enum("category"), nullable=False),
        sa.Column("language", _enum("language"), nullable=False, server_default="zh-CN"),
        sa.Column("source_type", _enum("content_source_type"), nullable=False),
        sa.Column("is_original", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column("source_url", sa.Text()),
        sa.Column("source_platform", sa.String(50)),
        sa.Column("original_author_name", sa.String(100)),
        sa.Column("original_author_url", sa.Text()),
        sa.Column("cover_media_url", sa.Text()),
        sa.Column("allow_how_to_interest", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        sa.Column("service_enabled", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column("service_note", sa.Text()),
        sa.Column("tools", postgresql.ARRAY(sa.Text()), nullable=False, server_default=sa.text("'{}'::text[]")),
        sa.Column("domains", postgresql.ARRAY(sa.Text()), nullable=False, server_default=sa.text("'{}'::text[]")),
        sa.Column("ai_badge", sa.String(20), nullable=False, server_default="none"),
        sa.Column("ai_implementation_hint", sa.Text()),
        sa.Column("target_users", postgresql.ARRAY(sa.Text())),
        sa.Column("use_cases", postgresql.ARRAY(sa.Text())),
        sa.Column("featured_rank", sa.Integer()),
        sa.Column("status", _enum("project_status"), nullable=False, server_default="draft"),
        sa.Column("hot_score", sa.Float(), nullable=False, server_default=sa.text("0")),
        sa.Column("published_at", postgresql.TIMESTAMP(timezone=True)),
        _created_at(),
        _updated_at(),
        sa.Column("deleted_at", postgresql.TIMESTAMP(timezone=True)),
        sa.CheckConstraint(f"domains <@ ARRAY[{_quoted(DOMAIN)}]::text[]", name="domains_allowed"),
        sa.CheckConstraint(f"ai_badge IN ({_quoted(AI_BADGE)})", name="ai_badge_allowed"),
    )
    op.create_index("ix_projects_status_published_at", "projects", ["status", "published_at"])
    op.create_index("ix_projects_category_status", "projects", ["category", "status"])
    op.create_index("ix_projects_hot_score", "projects", ["hot_score"])
    op.create_index("ix_projects_featured_rank", "projects", ["featured_rank"])
    op.create_index("ix_projects_domains_gin", "projects", ["domains"], postgresql_using="gin")
    op.create_index("ix_projects_tools_gin", "projects", ["tools"], postgresql_using="gin")
    # 全文索引（字段·API v1.3 §11）：MVP 先覆盖标题+亮点；tools/domains 检索由上面两个 GIN 承担，
    # tags 在关系表里单独可查。中文分词是已知局限，搜索升级时再换 pg_trgm/zhparser。
    op.execute(
        "CREATE INDEX ix_projects_fulltext ON projects USING gin "
        "(to_tsvector('simple', coalesce(title, '') || ' ' || coalesce(tagline, '')))"
    )

    # ---------- 4. project_media 媒体画廊 ----------
    op.create_table(
        "project_media",
        _uuid_pk(),
        sa.Column("project_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("projects.id"), nullable=False),
        sa.Column("media_type", sa.String(20), nullable=False),
        sa.Column("url", sa.Text(), nullable=False),
        sa.Column("thumbnail_url", sa.Text()),
        sa.Column("sort_order", sa.Integer(), nullable=False, server_default=sa.text("0")),
        _created_at(),
        sa.CheckConstraint("media_type IN ('image', 'video')", name="media_type_allowed"),
    )
    op.create_index("ix_project_media_project_id", "project_media", ["project_id"])

    # ---------- 5. project_tags 标签字典 + project_tag_relations 关系 ----------
    op.create_table(
        "project_tags",
        _uuid_pk(),
        sa.Column("name", sa.String(50), nullable=False),
        _created_at(),
        sa.UniqueConstraint("name", name="uq_project_tags_name"),
    )
    op.create_table(
        "project_tag_relations",
        _uuid_pk(),
        sa.Column("project_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("projects.id"), nullable=False),
        sa.Column("tag_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("project_tags.id"), nullable=False),
        _created_at(),
        sa.UniqueConstraint("project_id", "tag_id", name="uq_project_tag_relations_project_tag"),
    )
    op.create_index("ix_project_tag_relations_tag_id", "project_tag_relations", ["tag_id"])

    # ---------- 6. favorites 收藏 / try_items 想试 ----------
    op.create_table(
        "favorites",
        _uuid_pk(),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("project_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("projects.id"), nullable=False),
        _created_at(),
        sa.UniqueConstraint("user_id", "project_id", name="uq_favorites_user_project"),
    )
    op.create_index("ix_favorites_project_id", "favorites", ["project_id"])

    op.create_table(
        "try_items",
        _uuid_pk(),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("project_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("projects.id"), nullable=False),
        _created_at(),
        sa.UniqueConstraint("user_id", "project_id", name="uq_try_items_user_project"),
    )
    op.create_index("ix_try_items_project_id", "try_items", ["project_id"])

    # ---------- 7. how_to_interests 想看怎么做（主信号，游客可写） ----------
    # 红线：user_id 可空；登录用户与游客分别用部分唯一索引去重
    op.create_table(
        "how_to_interests",
        _uuid_pk(),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id")),
        sa.Column("anon_client_id", sa.String(64)),
        sa.Column("project_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("projects.id"), nullable=False),
        _created_at(),
        sa.CheckConstraint("user_id IS NOT NULL OR anon_client_id IS NOT NULL", name="identity_present"),
    )
    op.create_index(
        "uq_how_to_interests_user_project",
        "how_to_interests",
        ["user_id", "project_id"],
        unique=True,
        postgresql_where=sa.text("user_id IS NOT NULL"),
    )
    op.create_index(
        "uq_how_to_interests_anon_project",
        "how_to_interests",
        ["anon_client_id", "project_id"],
        unique=True,
        postgresql_where=sa.text("user_id IS NULL"),
    )
    op.create_index("ix_how_to_interests_project_id", "how_to_interests", ["project_id"])

    # ---------- 8. clue_subscriptions 线索订阅 ----------
    op.create_table(
        "clue_subscriptions",
        _uuid_pk(),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("project_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("projects.id"), nullable=False),
        _created_at(),
        sa.UniqueConstraint("user_id", "project_id", name="uq_clue_subscriptions_user_project"),
    )
    op.create_index("ix_clue_subscriptions_project_id", "clue_subscriptions", ["project_id"])

    # ---------- 9. similar_project_links 我做了类似的 ----------
    op.create_table(
        "similar_project_links",
        _uuid_pk(),
        sa.Column("source_project_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("projects.id"), nullable=False),
        sa.Column("similar_project_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("projects.id"), nullable=False),
        _created_at(),
        sa.UniqueConstraint("source_project_id", "similar_project_id", name="uq_similar_links_source_similar"),
    )
    op.create_index("ix_similar_links_source", "similar_project_links", ["source_project_id"])
    op.create_index("ix_similar_links_similar", "similar_project_links", ["similar_project_id"])

    # ---------- 10. project_reactions 创意反馈（可取消） ----------
    op.create_table(
        "project_reactions",
        _uuid_pk(),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("project_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("projects.id"), nullable=False),
        sa.Column("reaction_type", _enum("reaction_type"), nullable=False),
        _created_at(),
        sa.UniqueConstraint("user_id", "project_id", "reaction_type", name="uq_reactions_user_project_type"),
    )
    op.create_index("ix_project_reactions_project_id", "project_reactions", ["project_id"])

    # ---------- 11. shares 分享 ----------
    op.create_table(
        "shares",
        _uuid_pk(),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id")),
        sa.Column("anon_client_id", sa.String(64)),
        sa.Column("project_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("projects.id"), nullable=False),
        sa.Column("share_channel", _enum("share_channel"), nullable=False),
        sa.Column("share_status", _enum("share_status"), nullable=False),
        _created_at(),
    )
    op.create_index("ix_shares_project_status_channel", "shares", ["project_id", "share_status", "share_channel"])

    # ---------- 12. reports 举报 ----------
    op.create_table(
        "reports",
        _uuid_pk(),
        sa.Column("reporter_user_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("project_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("projects.id"), nullable=False),
        sa.Column("reason", sa.String(50), nullable=False),
        sa.Column("description", sa.Text()),
        sa.Column("status", _enum("report_status"), nullable=False, server_default="pending"),
        sa.Column("handled_by_user_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id")),
        sa.Column("handled_at", postgresql.TIMESTAMP(timezone=True)),
        sa.Column("resolution_note", sa.Text()),
        _created_at(),
        _updated_at(),
    )
    op.create_index("ix_reports_status_created_at", "reports", ["status", "created_at"])
    op.create_index("ix_reports_project_id", "reports", ["project_id"])

    # ---------- 13. notifications 通知 ----------
    op.create_table(
        "notifications",
        _uuid_pk(),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("type", _enum("notification_type"), nullable=False),
        sa.Column("title", sa.String(200), nullable=False),
        sa.Column("body", sa.Text()),
        sa.Column("project_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("projects.id")),
        sa.Column("is_read", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column("read_at", postgresql.TIMESTAMP(timezone=True)),
        _created_at(),
    )
    op.create_index("ix_notifications_user_read_created", "notifications", ["user_id", "is_read", "created_at"])

    # ---------- 14. push_preferences 推送偏好 ----------
    op.create_table(
        "push_preferences",
        _uuid_pk(),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("daily_pick_enabled", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        sa.Column("weekly_ranking_enabled", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        sa.Column("how_to_interest_enabled", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        sa.Column("clue_update_enabled", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        sa.Column("similar_project_enabled", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        sa.Column("content_status_enabled", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        sa.Column("system_enabled", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        sa.Column("interaction_enabled", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        _created_at(),
        _updated_at(),
        sa.UniqueConstraint("user_id", name="uq_push_preferences_user_id"),
    )

    # ---------- 15. candidate_contents AI 候选池 ----------
    op.create_table(
        "candidate_contents",
        _uuid_pk(),
        sa.Column("status", _enum("candidate_status"), nullable=False, server_default="ai_collected"),
        sa.Column("title", sa.String(80)),
        sa.Column("tagline", sa.String(140)),
        sa.Column("summary", sa.String(500)),
        sa.Column("description", sa.Text()),
        sa.Column("category", _enum("category")),
        sa.Column("language", _enum("language"), nullable=False, server_default="zh-CN"),
        sa.Column("domains", postgresql.ARRAY(sa.Text()), nullable=False, server_default=sa.text("'{}'::text[]")),
        sa.Column("tools", postgresql.ARRAY(sa.Text()), nullable=False, server_default=sa.text("'{}'::text[]")),
        sa.Column("tags_json", postgresql.JSONB()),
        sa.Column("ai_implementation_hint", sa.Text()),
        sa.Column("target_users", postgresql.ARRAY(sa.Text())),
        sa.Column("use_cases", postgresql.ARRAY(sa.Text())),
        sa.Column("source_url", sa.Text()),
        sa.Column("source_platform", sa.String(50)),
        sa.Column("original_author_name", sa.String(100)),
        sa.Column("original_author_url", sa.Text()),
        sa.Column("cover_media_url", sa.Text()),
        sa.Column("media_json", postgresql.JSONB()),
        sa.Column("scores_json", postgresql.JSONB()),
        sa.Column("ai_curation_score", sa.Integer()),
        sa.Column("risk_flags", postgresql.ARRAY(sa.Text()), nullable=False, server_default=sa.text("'{}'::text[]")),
        sa.Column("risk_note", sa.Text()),
        sa.Column("reviewed_by_user_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id")),
        sa.Column("reviewed_at", postgresql.TIMESTAMP(timezone=True)),
        sa.Column("project_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("projects.id")),
        _created_at(),
        _updated_at(),
    )
    op.create_index("ix_candidate_contents_status_created", "candidate_contents", ["status", "created_at"])
    op.create_index("ix_candidate_contents_score", "candidate_contents", ["ai_curation_score"])

    # ---------- 16. admin_actions 操作日志 ----------
    op.create_table(
        "admin_actions",
        _uuid_pk(),
        sa.Column("admin_user_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("action", sa.String(50), nullable=False),
        sa.Column("target_type", sa.String(30), nullable=False),
        sa.Column("target_id", postgresql.UUID(as_uuid=True)),
        sa.Column("detail", postgresql.JSONB()),
        _created_at(),
    )
    op.create_index("ix_admin_actions_admin_created", "admin_actions", ["admin_user_id", "created_at"])
    op.create_index("ix_admin_actions_target", "admin_actions", ["target_type", "target_id"])

    # ---------- 17. analytics_events 埋点（无外键：高频写入 + 允许游客事件） ----------
    op.create_table(
        "analytics_events",
        _uuid_pk(),
        sa.Column("user_id", postgresql.UUID(as_uuid=True)),
        sa.Column("event_name", sa.String(50), nullable=False),
        sa.Column("project_id", postgresql.UUID(as_uuid=True)),
        sa.Column("event_payload", postgresql.JSONB()),
        sa.Column("client_info", postgresql.JSONB()),
        _created_at(),
    )
    op.create_index("ix_analytics_events_name_created", "analytics_events", ["event_name", "created_at"])
    op.create_index("ix_analytics_events_project_id", "analytics_events", ["project_id"])


def downgrade() -> None:
    # 按依赖反序删表，再删枚举类型
    for table in (
        "analytics_events",
        "admin_actions",
        "candidate_contents",
        "push_preferences",
        "notifications",
        "reports",
        "shares",
        "project_reactions",
        "similar_project_links",
        "clue_subscriptions",
        "how_to_interests",
        "try_items",
        "favorites",
        "project_tag_relations",
        "project_tags",
        "project_media",
        "projects",
        "users",
    ):
        op.drop_table(table)
    for name in ENUM_TYPES:
        op.execute(f'DROP TYPE "{name}"')
