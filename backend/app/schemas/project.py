# ============================================================
# 这个文件是干什么的：定义项目相关接口的数据形状，包括列表、详情、发布和新版动作按钮。
# 它对应产品里的什么功能：发现流、项目详情、发布页、实现线索页、榜单页。
# 如果它出错了，用户会看到什么现象：信息流刷不出来、发布被误拒、详情按钮或统计空白。
# ============================================================
import uuid
from datetime import datetime
from enum import Enum
from typing import List, Optional

from pydantic import BaseModel, Field, field_validator, model_validator

from app.schemas.common import (
    AiBadge,
    Category,
    ContentType,
    ContentSourceType,
    Domain,
    Language,
    ProjectStatus,
)
from app.schemas.media import MediaType
from app.schemas.user import UserBrief


def _check_tag_items(v):
    """H-MDL-9：tags 元素长度校验（1-50 字符），供 ProjectCreate/ProjectUpdate 复用。"""
    if v is None:
        return v
    for t in v:
        if not isinstance(t, str) or len(t) < 1 or len(t) > 50:
            raise ValueError("每个标签长度需在 1-50 之间")
    return v


def _check_tool_items(v):
    """H-API-7：tools 元素长度校验（≤30 字符），供 ProjectCreate/ProjectUpdate 复用。"""
    if v is None:
        return v
    for t in v:
        if not isinstance(t, str) or len(t) > 30:
            raise ValueError("每个工具名长度需 ≤30 字符")
    return v



class MediaItem(BaseModel):
    # 前端读 type/poster（见 frontend project_card_dto）。字段直接命名 type/poster，
    # 构造处显式传 type=m.media_type / poster=m.thumbnail_url（见 services/projects.py）。
    # 不能用 Field(alias="media_type")：FastAPI 响应默认 by_alias=True 会把输出又变回
    # media_type/thumbnail_url，等于没改（PR#3 原写法即此坑，已改为裸字段名）。
    id: uuid.UUID
    type: MediaType
    kind: Optional[MediaType] = Field(None, description="新版前端别名；值与 type 一致")
    url: str
    poster: Optional[str] = Field(None, description="视频封面；前端读 poster")
    sort_order: int = 0


class ProjectActionType(str, Enum):
    take = "take"
    go = "go"
    how = "how"


class ProjectActionSub(str, Enum):
    text = "text"
    file = "file"
    github = "github"
    appstore = "appstore"
    url = "url"
    workflow = "workflow"


class ProjectActionEventType(str, Enum):
    click = "click"
    success = "success"


class ProjectActionInput(BaseModel):
    action_type: ProjectActionType = Field(alias="type")
    action_sub: ProjectActionSub = Field(alias="sub")
    label: str = Field(min_length=1, max_length=255)
    sublabel: Optional[str] = Field(None, max_length=255)
    content: Optional[str] = Field(None, max_length=4000)
    file_media_id: Optional[uuid.UUID] = None
    file_name: Optional[str] = Field(None, max_length=255, alias="fileName")
    file_size_bytes: Optional[int] = Field(None, ge=0, alias="fileSize")
    url: Optional[str] = Field(None, max_length=1000)
    sort_order: int = Field(0, ge=0, alias="sortOrder")

    model_config = {"populate_by_name": True}


class ProjectActionOut(BaseModel):
    id: uuid.UUID
    action_type: ProjectActionType = Field(alias="type")
    action_sub: ProjectActionSub = Field(alias="sub")
    label: str
    sublabel: Optional[str] = None
    content: Optional[str] = None
    file_media_id: Optional[uuid.UUID] = None
    file_name: Optional[str] = Field(None, alias="fileName")
    file_size_bytes: Optional[int] = Field(None, alias="fileSize")
    url: Optional[str] = None
    sort_order: int = Field(0, alias="sortOrder")

    model_config = {"populate_by_name": True}


class ProjectActionEventCreate(BaseModel):
    event_type: ProjectActionEventType = Field(alias="eventType")
    anon_client_id: Optional[str] = Field(None, max_length=64, alias="anonClientId")

    model_config = {"populate_by_name": True}


class ProjectActionEventResponse(BaseModel):
    ok: bool = True
    action_event_id: uuid.UUID
    takeaway_count: int = 0


class ReactionCounts(BaseModel):
    creative: int = 0
    big_brain: int = 0
    cool: int = 0


class ProjectCounts(BaseModel):
    """详情页与分享卡展示的计数。"""

    favorites: int = 0
    tries: int = 0
    how_to_interests: int = 0
    shares_completed: int = 0
    action_clicks: int = 0
    takeaways: int = 0
    reactions: ReactionCounts = ReactionCounts()


class ViewerState(BaseModel):
    """当前请求者与该项目的关系；游客全为 false/空。"""

    is_favorited: bool = False
    is_tried: bool = False
    has_how_to_interest: bool = False
    is_following_author: bool = False
    reactions: List[str] = Field(default=[], description="我点过的反应类型")


class ProjectCard(BaseModel):
    """列表卡片；旧字段保持，新版前端字段补充为可选或可推导。
    
    字段语义说明（card_from_project 组装逻辑）：
    - subtitle：实际取值为 tagline，为兼容旧版前端保留
    - intro：fallback 优先级：intro > description > summary，取第一个非空值
    - flag：仅当 ai_badge != "none" 时有值，否则为 null
    - author：列表端点填充 UserBrief，详情端点填充完整作者信息
    - counts：列表端点填充真实计数，详情端点填充完整计数
    """

    id: uuid.UUID
    title: str
    tagline: str
    subtitle: Optional[str] = Field(None, description="兼容字段，实际值与 tagline 相同")
    intro: Optional[str] = Field(None, description="简介，fallback: intro > description > summary")
    vertical: Optional[str] = None
    flag: Optional[str] = Field(None, description="AI 标记展示值，仅当 ai_badge != 'none' 时非空")
    takeaway_count: int = 0
    repo_stars: Optional[str] = None
    cover_media_url: Optional[str] = None
    category: Category
    content_type: Optional[ContentType] = Field(None, description="内容类型（成果类型），可空")
    domains: List[Domain]
    tools: List[str]
    ai_badge: AiBadge
    author: Optional[UserBrief] = Field(None, description="作者信息，列表端点填充")
    counts: Optional[ProjectCounts] = Field(None, description="互动计数，列表端点填充真实值")
    viewer: Optional[ViewerState] = None
    published_at: Optional[datetime] = None
    linked_at: Optional[datetime] = None
    status: ProjectStatus


class ProjectDetail(ProjectCard):
    """详情页字段，覆盖旧详情和新版 Flutter 详情两种形态。"""

    summary: str
    description: Optional[str] = None
    language: Language
    source_type: ContentSourceType
    is_original: bool
    source_url: Optional[str] = None
    source_platform: Optional[str] = None
    original_author_name: Optional[str] = None
    original_author_url: Optional[str] = None
    try_url: Optional[str] = Field(None, description="体验链接：作者作品的可去用地址，前端「去体验」打开")
    media: List[MediaItem] = []
    actions: List[ProjectActionOut] = []
    tags: List[str] = []
    ai_implementation_hint: Optional[str] = Field(None, description="AI 推测思路，展示时需标注")
    target_users: List[str] = []
    use_cases: List[str] = []
    allow_how_to_interest: bool = True
    author: Optional[UserBrief] = Field(None, description="外部抓取内容为 null")
    counts: ProjectCounts = ProjectCounts()
    viewer: ViewerState = ViewerState()
    related_projects: List[ProjectCard] = []
    other_projects: List[ProjectCard] = []
    created_at: datetime


class ProjectCreate(BaseModel):
    """POST /projects。旧版完整字段可继续用，新版可用 intro/vertical/actions/media_ids/source_kind。"""

    title: Optional[str] = Field(None, min_length=2, max_length=80)
    tagline: Optional[str] = Field(None, min_length=5, max_length=140)
    summary: Optional[str] = Field(None, min_length=20, max_length=500)
    description: Optional[str] = Field(None, max_length=1000)
    intro: Optional[str] = Field(None, min_length=1, max_length=4000)
    vertical: Optional[str] = Field(None, max_length=50)
    repo_stars: Optional[str] = Field(None, max_length=20)
    category: Optional[Category] = None
    domains: List[Domain] = Field(default=[])
    # H-API-7：tools 数量上限 20，元素长度 ≤30
    tools: List[str] = Field(default=[], max_length=20, description="准入字段：tools>=1 或 description/intro 含可复现说明")
    # H-API-7：media_ids 数量上限 20
    media_ids: List[uuid.UUID] = Field(default=[], max_length=20, description="先调 POST /media 上传拿 id；新版允许无媒体但必须有方法/action")
    # H-API-7：actions 数量上限 20
    actions: List[ProjectActionInput] = Field(default=[], max_length=20)
    source_kind: Optional[str] = Field(None, description="新版前端：original/curated；服务端映射到 source_type")
    is_original: bool = True
    source_url: Optional[str] = Field(None, description="is_original=false 必填")
    try_url: Optional[str] = Field(None, max_length=2000, description="体验链接：作品的可去用地址(http/https)，让别人直接去用")
    original_author_name: Optional[str] = Field(None, max_length=100)
    # H-API-7：target_users / use_cases 数量上限 10
    target_users: List[str] = Field(default=[], max_length=10)
    use_cases: List[str] = Field(default=[], max_length=10)
    allow_how_to_interest: bool = True
    related_original_project_id: Optional[uuid.UUID] = Field(
        None, description="从'我做了类似的'入口带入；发布后自动建 similar_project_links"
    )
    # H-MDL-9：tags 数量上限 20，元素长度 1-50
    tags: List[str] = Field(default=[], max_length=20)

    @field_validator("tags", mode="after")
    @classmethod
    def _check_tag_len(cls, v):
        return _check_tag_items(v)

    @field_validator("tools", mode="after")
    @classmethod
    def _check_tool_len(cls, v):
        return _check_tool_items(v)

    @model_validator(mode="after")
    def check_rules(self):
        is_v2 = bool(self.intro or self.vertical or self.actions or self.source_kind)
        if not is_v2:
            missing = []
            for field in ("title", "tagline", "summary", "category"):
                if getattr(self, field) in (None, "", []):
                    missing.append(field)
            if not self.domains:
                missing.append("domains")
            if not self.media_ids:
                missing.append("media_ids")
            if missing:
                raise ValueError(f"旧版发布字段缺失：{', '.join(missing)}")
        if self.source_kind and self.source_kind not in ("original", "curated", "user_original", "user_discovery"):
            raise ValueError("source_kind 只能是 original/curated/user_original/user_discovery")
        if not self.is_original and not self.source_url:
            raise ValueError("非原创内容必须提供 source_url")
        if self.related_original_project_id and not self.is_original:
            raise ValueError("从'我做了类似的'入口发布时 is_original 必须为 true")
        if self.try_url and not (self.try_url.startswith("http://") or self.try_url.startswith("https://")):
            raise ValueError("体验链接必须是 http/https 网址")
        return self


class ProjectUpdate(BaseModel):
    """PATCH /projects/{id}：只传想改的字段，只能改自己的项目。"""

    title: Optional[str] = Field(None, min_length=2, max_length=80)
    tagline: Optional[str] = Field(None, min_length=5, max_length=140)
    summary: Optional[str] = Field(None, min_length=20, max_length=500)
    description: Optional[str] = Field(None, max_length=1000)
    intro: Optional[str] = Field(None, min_length=1, max_length=4000)
    vertical: Optional[str] = Field(None, max_length=50)
    repo_stars: Optional[str] = Field(None, max_length=20)
    category: Optional[Category] = None
    domains: Optional[List[Domain]] = Field(None, min_length=1)
    # H-API-7：tools 数量上限 20，元素长度 ≤30
    tools: Optional[List[str]] = Field(None, max_length=20)
    media_ids: Optional[List[uuid.UUID]] = Field(None, min_length=1, max_length=20)
    target_users: Optional[List[str]] = Field(None, max_length=10)
    use_cases: Optional[List[str]] = Field(None, max_length=10)
    allow_how_to_interest: Optional[bool] = None
    try_url: Optional[str] = Field(None, max_length=2000, description="体验链接(http/https)")
    # H-MDL-9：tags 数量上限 20，元素长度 1-50
    tags: Optional[List[str]] = Field(None, max_length=20)

    @field_validator("tags", mode="after")
    @classmethod
    def _check_tag_len(cls, v):
        return _check_tag_items(v)

    @field_validator("tools", mode="after")
    @classmethod
    def _check_tool_len(cls, v):
        return _check_tool_items(v)


class SimilarProjectsResponse(BaseModel):
    """GET /projects/{id}/similar：仅返回 status=published 的类似作品。"""

    items: List[ProjectCard]


class ImplementationClue(BaseModel):
    """GET /projects/{id}/implementation-clue：实现线索页，游客可读。"""

    project_id: uuid.UUID
    source_url: Optional[str] = None
    source_platform: Optional[str] = None
    original_author_name: Optional[str] = None
    original_author_url: Optional[str] = None
    tools: List[str] = []
    ai_implementation_hint: Optional[str] = None
    related_projects: List[ProjectCard] = []
    how_to_interest_count: int = 0


class RankedItem(BaseModel):
    rank: int
    project: ProjectCard


class RankingResponse(BaseModel):
    """GET /rankings：MVP 三类 weekly_hot/latest/today_pick。"""

    type: str
    generated_at: datetime
    items: List[RankedItem]


class AuthorRankOut(BaseModel):
    """GET /rankings/authors：作者榜一项——总获赞（项目反应+动态赞）+ 项目/动态数。"""

    user_id: uuid.UUID
    nickname: Optional[str] = None
    avatar_url: Optional[str] = None
    total_likes: int
    project_count: int
    post_count: int
