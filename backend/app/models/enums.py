# ============================================================
# 这个文件是干什么的：全部"固定选项清单"（枚举）的唯一定义处——
#   比如项目有哪 7 种状态、内容分 12 类、领域有哪 10 个，全在这里，一字不差照字段·API v1.3 §3。
# 它对应产品里的什么功能：审核状态机、分类筛选、"看我这行"领域筛选、通知类型等。
# 如果它出错了，用户会看到什么现象：内容状态错乱（如下架的还在显示）、筛选分类对不上、通知发错类型。
# ============================================================
from sqlalchemy.dialects.postgresql import ENUM

# ---- 项目生命周期（PRD v1.3 §8.4 唯一真源）----
# 红线：下架=taken_down、删除=deleted，两者分开，不合成 removed
PROJECT_STATUS = ("draft", "published", "hidden", "under_review", "rejected", "taken_down", "deleted")

# ---- AI 候选池流水（PRD v1.3 §8.4 唯一真源）----
# 红线：用 approved/parked/discarded，不用 published/saved/rejected
CANDIDATE_STATUS = ("ai_collected", "ai_processed", "pending_review", "edited", "approved", "parked", "discarded")

# ---- 12 个一级分类（字段·API v1.3 §3；与 PRD §9.1 的 automation 冲突时以本处 automation_tools 为准）----
CATEGORY = (
    "fun_ideas", "image_design", "video_music", "life_utility", "work_efficiency", "learning_growth",
    "business_ideas", "automation_tools", "creator_tools", "ai_apps", "weird_fun", "future_cases",
)

# ---- 领域（"看我这行"筛选）：存在 text[] 列里，用 CHECK 约束限定取值 ----
DOMAIN = ("dev", "design", "video", "marketing", "writing", "education", "ecommerce", "office", "cad_3d", "other")

# ---- 内容类型（前端「看看」筛选/兴趣用的成果类型；与 CATEGORY 用途、DOMAIN 职业正交，不删那两套）----
# project.content_type 单选（可空，旧数据按 category 回填）；user.interest_content_types 多选。
CONTENT_TYPE = ("ai_image", "ai_video", "web", "app", "tool", "opensource", "prompt")

# ---- 内容来源 ----
CONTENT_SOURCE_TYPE = ("ai_crawled", "manual_import", "user_original", "user_discovery")

# ---- 创意反馈（可取消 toggle）----
REACTION_TYPE = ("creative", "big_brain", "cool")

# ---- 分享 ----
SHARE_STATUS = ("clicked", "completed")
SHARE_CHANNEL = ("wechat", "moments", "x", "xiaohongshu", "copy_link", "other")

# ---- 通知类型 ----
NOTIFICATION_TYPE = (
    "daily_pick", "weekly_ranking", "how_to_interest", "clue_update",
    "similar_project", "content_status", "system", "interaction",
)

# ---- 举报处理状态 ----
REPORT_STATUS = ("pending", "processing", "resolved", "rejected")

# ---- 内容/用户语言 ----
LANGUAGE = ("zh-CN", "en-US")

# ---- AI 策展徽章（字段·API v1.3 §4.3 定为 varchar(20)，故不建数据库枚举类型，用 CHECK 限定）----
AI_BADGE = ("worth_a_look", "high_potential", "staff_pick", "none")

# ---- 用户角色（varchar(20) + CHECK，可空）----
USER_ROLE = ("creator", "developer", "general")


def _pg_enum(name: str, values: tuple) -> ENUM:
    # create_type=False：枚举类型由 Alembic 迁移脚本统一创建，模型只引用
    return ENUM(*values, name=name, create_type=False)


project_status_enum = _pg_enum("project_status", PROJECT_STATUS)
candidate_status_enum = _pg_enum("candidate_status", CANDIDATE_STATUS)
category_enum = _pg_enum("category", CATEGORY)
content_type_enum = _pg_enum("content_type", CONTENT_TYPE)
content_source_type_enum = _pg_enum("content_source_type", CONTENT_SOURCE_TYPE)
reaction_type_enum = _pg_enum("reaction_type", REACTION_TYPE)
share_status_enum = _pg_enum("share_status", SHARE_STATUS)
share_channel_enum = _pg_enum("share_channel", SHARE_CHANNEL)
notification_type_enum = _pg_enum("notification_type", NOTIFICATION_TYPE)
report_status_enum = _pg_enum("report_status", REPORT_STATUS)
language_enum = _pg_enum("language", LANGUAGE)


def quoted_list(values: tuple) -> str:
    """生成 CHECK 约束里用的 'a','b','c' 字符串。"""
    return ", ".join(f"'{v}'" for v in values)
