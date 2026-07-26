# ============================================================
# 这个文件是干什么的：定义全部后台管理接口的数据形状——候选池审核、已发布项目管理、
#   需求看板、举报处理、数据看板、每日精选推送、操作日志。
# 它对应产品里的什么功能：运营后台的所有页面（字段·API v1.3 §9 + 后台 v1.2）。
# 如果它出错了，用户会看到什么现象：用户不直接可见，但运营无法审核内容→App 断供，
#   无法处理举报→违规内容滞留。
# ============================================================
import uuid
from datetime import datetime
from enum import Enum
from typing import Any, List, Literal, Optional

from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.schemas.common import (
    CandidateStatus,
    Category,
    ContentSourceType,
    Domain,
    Language,
    ProjectStatus,
    ReportStatus,
)
from app.schemas.interaction import ReportReason

# ---------- 候选池 ----------


class CandidateListItem(BaseModel):
    """GET /admin/candidates 列表项（支持按状态/风险/分数/来源/语言筛选）。"""

    model_config = ConfigDict(from_attributes=True)  # 允许直接从 ORM 候选对象生成

    id: uuid.UUID
    status: CandidateStatus
    content_kind: str = Field("project", description="project=项目 / post=动态（马甲发的动态需单独审）")
    source_type: ContentSourceType = Field(description="ai_crawled / manual_import（迁移 0002 补充）")
    title: Optional[str] = None
    tagline: Optional[str] = None
    category: Optional[Category] = None
    language: Language
    domains: List[Domain] = []
    tools: List[str] = []
    source_platform: Optional[str] = None
    cover_media_url: Optional[str] = None
    ai_curation_score: Optional[int] = None
    risk_flags: List[str] = []
    project_id: Optional[uuid.UUID] = Field(None, description="approve 后回写的正式项目 ID")
    created_at: datetime


class CandidateDetail(CandidateListItem):
    summary: Optional[str] = None
    description: Optional[str] = None
    tags_json: Optional[Any] = Field(None, description="列表或 {tags:[...]}，approve 时拆进标签表")
    ai_implementation_hint: Optional[str] = None
    target_users: List[str] = []
    use_cases: List[str] = []
    source_url: Optional[str] = None
    original_author_name: Optional[str] = None
    original_author_url: Optional[str] = None
    media_json: Optional[Any] = Field(None, description="列表或 {items:[...]}，每项 {url, media_type, thumbnail_url?}")
    scores_json: Optional[Any] = None
    risk_note: Optional[str] = None
    reviewed_by_user_id: Optional[uuid.UUID] = None
    reviewed_at: Optional[datetime] = None
    updated_at: datetime

    @field_validator("target_users", "use_cases", mode="before")
    @classmethod
    def _none_to_empty(cls, v):
        # 库里这两列可空：None 统一转 []，客户端不用处理 null
        # H-MDL-12：所有字段声明移到 validator 之前，避免 Pydantic 把后续行当 class var
        return v or []


class CandidatePatch(BaseModel):
    """PATCH /admin/candidates/{id}：人工编辑候选字段，保存后状态自动 → edited。"""

    title: Optional[str] = Field(None, min_length=2, max_length=80)
    tagline: Optional[str] = Field(None, min_length=5, max_length=140)
    summary: Optional[str] = Field(None, min_length=20, max_length=500)
    description: Optional[str] = Field(None, max_length=1000)
    category: Optional[Category] = None
    language: Optional[Language] = None
    domains: Optional[List[Domain]] = None
    tools: Optional[List[str]] = None
    tags_json: Optional[Any] = None
    ai_implementation_hint: Optional[str] = Field(
        None, description="只在'有把握'时保留（来源可访问+已识别工具+思路引用工具），否则置空"
    )
    target_users: Optional[List[str]] = None
    use_cases: Optional[List[str]] = None
    source_url: Optional[str] = None
    source_platform: Optional[str] = None
    original_author_name: Optional[str] = None
    original_author_url: Optional[str] = None
    cover_media_url: Optional[str] = None
    media_json: Optional[Any] = None
    risk_note: Optional[str] = None


class CandidateApproveResponse(BaseModel):
    """POST /admin/candidates/{id}/approve：复制建项目并发布（§5.3）。
    准入不满足返回 409 PUBLISH_GATE_FAILED；状态不允许返回 409 CANDIDATE_INVALID_STATE。"""

    ok: bool = True
    # 项目候选返回 project_id；动态（content_kind=post）候选返回 post_id。二者其一。
    project_id: Optional[uuid.UUID] = None
    post_id: Optional[uuid.UUID] = None
    # 实际随机派到的马甲昵称（审核员据此知道发布后作者显示成谁；预览页的名字是样例、以此为准）。
    persona_name: Optional[str] = None


class CandidateDiscardRequest(BaseModel):
    reason: Optional[str] = Field(None, max_length=500)


class CandidateManualCreate(BaseModel):
    """POST /admin/candidates/manual：把自己找到的链接手动加进候选池（跑 AI 整理后进待审队列）。"""

    url: str = Field(min_length=4, max_length=1000, description="要收录的链接（http/https）")
    title: Optional[str] = Field(None, max_length=80, description="不填则尝试抓页面标题，抓不到用域名")
    source_platform: Optional[str] = Field(None, max_length=40, description="来源平台名，缺省 manual")
    content_kind: Literal["project", "post"] = Field("project", description="落地为项目或动态，默认项目")


class CandidateManualCreateResponse(BaseModel):
    ok: bool = True
    candidate_id: Optional[uuid.UUID] = None
    duplicate: bool = Field(False, description="true=该链接已在候选池/已发布，未重复创建")
    fetched_title: Optional[str] = Field(None, description="抓到的页面标题（供前端回显确认）")


# ---------- 已发布项目管理 ----------


class AdminProjectListItem(BaseModel):
    id: uuid.UUID
    title: str
    status: ProjectStatus
    source_type: ContentSourceType
    category: Category
    author_user_id: Optional[uuid.UUID] = None
    featured_rank: Optional[int] = None
    hot_score: float = 0
    report_count: int = 0
    published_at: Optional[datetime] = None
    created_at: datetime


class AdminProjectActionRequest(BaseModel):
    """take-down / restore / soft-delete / require-edit 共用：理由写入 admin_actions 审计。"""

    reason: Optional[str] = Field(None, max_length=500)


class AdminProjectActionResponse(BaseModel):
    ok: bool = True
    status: ProjectStatus = Field(description="操作后的项目状态")


class FeatureRequest(BaseModel):
    """POST /admin/projects/{id}/feature：设置今日精选排序位；null=取消精选。"""

    featured_rank: Optional[int] = Field(None, ge=1, le=100)


# ---------- 需求看板（只读聚合，§5.5）----------


class DemandBoardItem(BaseModel):
    """外部内容（ai_crawled/manual_import/user_discovery）的想看怎么做聚合，按需求数降序。"""

    project_id: uuid.UUID
    title: str
    cover_media_url: Optional[str] = None
    source_type: ContentSourceType
    source_platform: Optional[str] = None
    domains: List[Domain] = []
    demand_count: int
    last_demand_at: Optional[datetime] = None


# ---------- 举报处理 ----------


class AdminReportItem(BaseModel):
    id: uuid.UUID
    project_id: uuid.UUID
    project_title: Optional[str] = None
    reporter_user_id: uuid.UUID
    # H-MDL-5：用 ReportReason 枚举替代裸 str，与 models/report.CHECK 一致
    reason: ReportReason
    description: Optional[str] = None
    status: ReportStatus
    handled_by_user_id: Optional[uuid.UUID] = None
    handled_at: Optional[datetime] = None
    resolution_note: Optional[str] = None
    created_at: datetime


class ReportProjectAction(str, Enum):
    """处理举报时对项目的连带动作（后台 v1.2 §管理员动作映射）。"""

    ignore = "ignore"            # 忽略：项目状态不变
    mark_risk = "mark_risk"      # 标记风险 → under_review
    require_edit = "require_edit"  # 要求修改 → under_review + 通知作者
    take_down = "take_down"      # 下架 → taken_down
    soft_delete = "soft_delete"  # 删除 → deleted


class ReportResolveResult(str, Enum):
    """举报处理结论：仅 resolved（成立）/ rejected（不成立）两个值合法。
    与 ReportStatus（含 pending/processing）区分开，避免在 schema 层放过非法值、
    再到 service 层才 422。"""

    resolved = "resolved"
    rejected = "rejected"


class ReportResolveRequest(BaseModel):
    """POST /admin/reports/{id}/resolve。"""

    result: ReportResolveResult = Field(description="resolved=成立 / rejected=不成立")
    project_action: ReportProjectAction = ReportProjectAction.ignore
    note: Optional[str] = Field(None, max_length=500)


# ---------- 数据看板（主信号漏斗）----------


class DashboardFunnel(BaseModel):
    """主信号漏斗（PRD §13）：曝光→详情→想看怎么做→线索页下游动作。"""

    card_impressions: int = 0
    card_clicks: int = 0
    detail_views: int = 0
    how_to_interest_clicks: int = 0
    clue_views: int = 0
    clue_source_clicks: int = 0
    clue_tool_clicks: int = 0
    clue_related_clicks: int = 0


class DashboardResponse(BaseModel):
    period_start: datetime
    period_end: datetime
    funnel: DashboardFunnel
    how_to_interest_rate: float = Field(0, description="想看怎么做点击率 = how_to_clicks / detail_views")
    clue_downstream_rate: float = Field(0, description="线索页下游转化 = (source+tool+related+subscribe) / clue_views")
    published_projects: int = 0
    pending_candidates: int = 0
    open_reports: int = 0


# ---------- 每日精选推送 ----------


class DailyPickPushRequest(BaseModel):
    project_id: uuid.UUID
    title_override: Optional[str] = Field(None, max_length=200, description="不传则用默认文案")
    body_override: Optional[str] = Field(None, max_length=500)


class DailyPickPushResponse(BaseModel):
    ok: bool = True
    audience_count: int = Field(0, description="按推送偏好过滤后的目标用户数")


# ---------- 操作日志 ----------


class AdminActionItem(BaseModel):
    id: uuid.UUID
    admin_user_id: uuid.UUID
    # action 是审计日志代码 f-string 生成的动态值（如 take_down_project / edit_candidate /
    # push_daily_pick），非固定枚举——保持裸 str，否则列表接口读到真实值会 500。
    action: str
    target_type: Literal["project", "candidate", "report", "user", "post", "feedback"]
    target_id: Optional[uuid.UUID] = None
    detail: Optional[dict] = None
    created_at: datetime


# ---------- 使用情况（真实用户/行为分析，回答"到底有没有人用"）----------
class ActiveUserItem(BaseModel):
    """窗口内活跃的登录用户 + 最近行为，用于判断是不是就自己人在用。"""
    user_id: uuid.UUID
    nickname: Optional[str] = None
    is_admin: bool = False
    event_count: int
    last_active: datetime


# ---------- 马甲号统一管理 ----------


class PersonaListItem(BaseModel):
    """GET /admin/personas 列表项：一个马甲号 + 它产出的内容量（初期内容质量把控用）。"""
    id: uuid.UUID
    nickname: Optional[str] = None
    handle: Optional[str] = None
    avatar_url: Optional[str] = None
    bio: Optional[str] = None
    project_count: int = 0        # 该马甲名下未删的项目数
    post_count: int = 0           # 该马甲名下未删的动态数
    total_post_likes: int = 0     # 动态获赞总数（粗看内容反响）
    last_active: Optional[datetime] = None  # 最近一条内容时间（项目/动态取较晚者）


class PersonaPostItem(BaseModel):
    """马甲名下一条动态（可就地删）。"""
    id: uuid.UUID
    content: str
    tags: List[str] = []
    quote_project_id: Optional[uuid.UUID] = None
    like_count: int = 0
    created_at: datetime


class PersonaProjectItem(BaseModel):
    """马甲名下一个项目（可就地下架/删）。"""
    id: uuid.UUID
    title: str
    status: ProjectStatus
    cover_media_url: Optional[str] = None
    hot_score: float = 0
    featured_rank: Optional[int] = None
    created_at: datetime


class PersonaContentResponse(BaseModel):
    """GET /admin/personas/{id}/content：某马甲最近的动态 + 项目，供逐条核查/删除。"""
    persona: PersonaListItem
    posts: List[PersonaPostItem]
    projects: List[PersonaProjectItem]


class PersonaUpdateRequest(BaseModel):
    """PATCH /admin/personas/{id}：后台改马甲的 昵称/签名/头像（都可选，只改传了的字段）。
    头像先经 POST /media 上传拿到 url，再把 url 传进来（或直接粘外链）。"""
    nickname: Optional[str] = Field(None, min_length=1, max_length=30)
    bio: Optional[str] = Field(None, max_length=200)
    avatar_url: Optional[str] = Field(None, max_length=500)


class UsageSummary(BaseModel):
    period_start: datetime
    period_end: datetime
    total_users: int          # 全部真实用户（非马甲、未注销）
    new_users: int            # 窗口内新注册
    active_users: int         # 窗口内有行为的登录用户数
    admin_active: int         # 其中管理员数（用于识别"是不是就我自己")
    dau_today: int            # 今天有行为的登录用户数
    guest_opens: int          # 游客 app_open 次数（无 user_id）
    event_breakdown: dict     # event_name -> 次数
    active_list: List[ActiveUserItem]
