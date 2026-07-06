# ============================================================
# 这个文件是干什么的：定义"AI 候选池表"——AI 从外部抓回来、还没正式发布的内容
#   都先存在这里，走完"AI整理→人工审核→通过"流水后才复制成正式项目。
# 它对应产品里的什么功能：后台审核工作台；用户在 App 里看到的 AI 抓取内容，全都先经过这张表。
# 如果它出错了，用户会看到什么现象：App 里新内容断供（候选进不来或发不出去），
#   或未审核的低质/侵权内容直接漏到了用户面前。
# ============================================================
import uuid
from datetime import datetime
from typing import Optional

from sqlalchemy import ForeignKey, Index, Integer, String, Text, text
from sqlalchemy.dialects.postgresql import ARRAY, JSONB, TIMESTAMP
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, TimestampMixin, uuid_pk
from app.models.enums import candidate_status_enum, category_enum, content_source_type_enum, language_enum


class CandidateContent(TimestampMixin, Base):
    __tablename__ = "candidate_contents"

    id: Mapped[uuid.UUID] = uuid_pk()
    # 红线：状态机用 ai_collected/ai_processed/pending_review/edited/approved/parked/discarded
    status: Mapped[str] = mapped_column(candidate_status_enum, nullable=False, server_default="ai_collected")
    # 候选来源（迁移 0002 补充）：ai_crawled 或 manual_import，approve 时原样带进项目
    source_type: Mapped[str] = mapped_column(content_source_type_enum, nullable=False, server_default="ai_crawled")

    # ---- AI 生成的内容字段（刚抓回来时可能还没生成，所以大多可空）----
    title: Mapped[Optional[str]] = mapped_column(String(80))
    tagline: Mapped[Optional[str]] = mapped_column(String(140))
    summary: Mapped[Optional[str]] = mapped_column(String(500))
    description: Mapped[Optional[str]] = mapped_column(Text)
    category: Mapped[Optional[str]] = mapped_column(category_enum)
    language: Mapped[str] = mapped_column(language_enum, nullable=False, server_default="zh-CN")
    domains: Mapped[list] = mapped_column(ARRAY(Text), nullable=False, server_default=text("'{}'::text[]"))
    tools: Mapped[list] = mapped_column(ARRAY(Text), nullable=False, server_default=text("'{}'::text[]"))
    # 标签先以 JSON 暂存，approve 时才拆解写入 project_tags / project_tag_relations（字段·API v1.3 §5.3）
    tags_json: Mapped[Optional[dict]] = mapped_column(JSONB)
    ai_implementation_hint: Mapped[Optional[str]] = mapped_column(Text)
    target_users: Mapped[Optional[list]] = mapped_column(ARRAY(Text))
    use_cases: Mapped[Optional[list]] = mapped_column(ARRAY(Text))

    # ---- 来源信息（外部内容必须保留，否则审核标风险）----
    source_url: Mapped[Optional[str]] = mapped_column(Text)
    source_platform: Mapped[Optional[str]] = mapped_column(String(50))
    original_author_name: Mapped[Optional[str]] = mapped_column(String(100))
    original_author_url: Mapped[Optional[str]] = mapped_column(Text)

    # ---- 媒体：候选阶段以 JSON 暂存，approve 时复制到 project_media（补全决策）----
    cover_media_url: Mapped[Optional[str]] = mapped_column(Text)
    media_json: Mapped[Optional[dict]] = mapped_column(JSONB)

    # ---- 抓取原料（迁移 0003）：原文标题/正文/媒体链接，AI 整理读它；整理后不删——
    #      PRD §10 外文处理要求"保留原文标题"，也留给审核比对防幻觉 ----
    raw_json: Mapped[Optional[dict]] = mapped_column(JSONB)

    # ---- AI 评分与风险（scores_json 留审计、不进 hot_score；分数单列一份便于后台筛选）----
    scores_json: Mapped[Optional[dict]] = mapped_column(JSONB)
    ai_curation_score: Mapped[Optional[int]] = mapped_column(Integer)  # 0-100，≥80 high_potential / 65-79 worth_a_look
    risk_flags: Mapped[list] = mapped_column(ARRAY(Text), nullable=False, server_default=text("'{}'::text[]"))
    risk_note: Mapped[Optional[str]] = mapped_column(Text)

    # ---- 审核流水 ----
    reviewed_by_user_id: Mapped[Optional[uuid.UUID]] = mapped_column(ForeignKey("users.id"))
    reviewed_at: Mapped[Optional[datetime]] = mapped_column(TIMESTAMP(timezone=True))
    # approve 后回写正式项目 ID（字段·API v1.3 §5.3）
    project_id: Mapped[Optional[uuid.UUID]] = mapped_column(ForeignKey("projects.id"))

    __table_args__ = (
        Index("ix_candidate_contents_status_created", "status", "created_at"),
        Index("ix_candidate_contents_score", "ai_curation_score"),
    )
