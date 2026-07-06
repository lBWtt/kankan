# ============================================================
# 这个文件是干什么的：定义"项目表"——产品最核心的一张表，每条记录就是一个
#   展示给用户看的 AI 创意用例（标题、亮点、用了什么工具、属于哪个行业、AI 实现思路等）。
# 它对应产品里的什么功能：发现页信息流、项目详情页、实现线索页、搜索、榜单、今日精选，全靠它。
# 如果它出错了，用户会看到什么现象：App 里一条内容都刷不出来，或内容字段错乱（如标题和工具对不上）。
# ============================================================
import uuid
from datetime import datetime
from typing import TYPE_CHECKING, Optional

from sqlalchemy import Boolean, CheckConstraint, Float, ForeignKey, Index, Integer, String, Text, text
from sqlalchemy.dialects.postgresql import ARRAY, TIMESTAMP
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, TimestampMixin, uuid_pk
from app.models.enums import (
    AI_BADGE,
    DOMAIN,
    category_enum,
    content_source_type_enum,
    language_enum,
    project_status_enum,
    quoted_list,
)

if TYPE_CHECKING:
    from app.models.user import User


class Project(TimestampMixin, Base):
    __tablename__ = "projects"

    id: Mapped[uuid.UUID] = uuid_pk()
    # AI 抓取/手动导入的内容没有站内作者，所以可空
    author_user_id: Mapped[Optional[uuid.UUID]] = mapped_column(ForeignKey("users.id"))
    # ORM 关系：lazy="raise" 防止隐式 lazy load，必须显式 selectinload
    author: Mapped[Optional["User"]] = relationship(lazy="raise")

    # 字段长度按字段·API v1.3 §4.3：标题 2-80、亮点 5-140、简介 20-500、详情 ≤1000（text）
    title: Mapped[str] = mapped_column(String(80), nullable=False)
    tagline: Mapped[str] = mapped_column(String(140), nullable=False)
    summary: Mapped[str] = mapped_column(String(500), nullable=False)
    description: Mapped[Optional[str]] = mapped_column(Text)
    intro: Mapped[Optional[str]] = mapped_column(Text)
    vertical: Mapped[Optional[str]] = mapped_column(String(50))
    takeaway_count: Mapped[int] = mapped_column(Integer, nullable=False, server_default=text("0"))
    repo_stars: Mapped[Optional[str]] = mapped_column(String(20))

    category: Mapped[str] = mapped_column(category_enum, nullable=False)
    language: Mapped[str] = mapped_column(language_enum, nullable=False, server_default="zh-CN")
    source_type: Mapped[str] = mapped_column(content_source_type_enum, nullable=False)
    is_original: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default=text("false"))
    source_url: Mapped[Optional[str]] = mapped_column(Text)
    source_platform: Mapped[Optional[str]] = mapped_column(String(50))
    original_author_name: Mapped[Optional[str]] = mapped_column(String(100))
    original_author_url: Mapped[Optional[str]] = mapped_column(Text)

    # PRD §8.5：主封面单独一个字段（发布准入要求必有，DB 层放宽以容纳草稿，准入在 API 层校验）
    cover_media_url: Mapped[Optional[str]] = mapped_column(Text)

    # 红线相关：想看怎么做开关，默认开
    allow_how_to_interest: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default=text("true"))
    # 服务化能力预留（仅占位，V1 不启用）
    service_enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default=text("false"))
    service_note: Mapped[Optional[str]] = mapped_column(Text)

    # ---- v1.3 新增字段 ----
    tools: Mapped[list] = mapped_column(ARRAY(Text), nullable=False, server_default=text("'{}'::text[]"))
    domains: Mapped[list] = mapped_column(ARRAY(Text), nullable=False, server_default=text("'{}'::text[]"))
    ai_badge: Mapped[str] = mapped_column(String(20), nullable=False, server_default="none")
    ai_implementation_hint: Mapped[Optional[str]] = mapped_column(Text)
    target_users: Mapped[Optional[list]] = mapped_column(ARRAY(Text))
    use_cases: Mapped[Optional[list]] = mapped_column(ARRAY(Text))
    featured_rank: Mapped[Optional[int]] = mapped_column(Integer)

    # 状态机（PRD §8.4）：draft/published/hidden/under_review/rejected/taken_down/deleted
    status: Mapped[str] = mapped_column(project_status_enum, nullable=False, server_default="draft")
    hot_score: Mapped[float] = mapped_column(Float, nullable=False, server_default=text("0"))
    published_at: Mapped[Optional[datetime]] = mapped_column(TIMESTAMP(timezone=True))
    deleted_at: Mapped[Optional[datetime]] = mapped_column(TIMESTAMP(timezone=True))

    __table_args__ = (
        CheckConstraint(f"domains <@ ARRAY[{quoted_list(DOMAIN)}]::text[]", name="domains_allowed"),
        CheckConstraint(f"ai_badge IN ({quoted_list(AI_BADGE)})", name="ai_badge_allowed"),
        # 字段·API v1.3 §11 要求的查询索引（全文索引在迁移脚本里用原生 SQL 建）
        Index("ix_projects_status_published_at", "status", "published_at"),
        Index("ix_projects_category_status", "category", "status"),
        Index("ix_projects_hot_score", "hot_score"),
        Index("ix_projects_featured_rank", "featured_rank"),
        Index("ix_projects_domains_gin", "domains", postgresql_using="gin"),
        Index("ix_projects_tools_gin", "tools", postgresql_using="gin"),
    )
