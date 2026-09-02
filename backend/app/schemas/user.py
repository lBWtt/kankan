# ============================================================
# 这个文件是干什么的：定义"我的资料"相关接口的数据形状——查看/修改个人信息、
#   推送偏好开关、onboarding 兴趣领域，以及别人看到的公开主页。
# 它对应产品里的什么功能："我的"页、设置页（语言/推送/兴趣）、首启兴趣采集、用户主页。
# 如果它出错了，用户会看到什么现象：个人页打不开、改了设置不生效、推送开关失灵。
# ============================================================
import uuid
from datetime import datetime
from typing import List, Optional

from pydantic import BaseModel, ConfigDict, Field

from app.schemas.common import ContentType, Domain, Language, UserRole


class MeResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)  # 允许直接从 ORM 用户对象生成

    id: uuid.UUID
    email: Optional[str] = None
    phone: Optional[str] = None
    handle: Optional[str] = None  # 稳定用户名 @handle（搜索/@/分享用）
    nickname: Optional[str] = None
    avatar_url: Optional[str] = None
    bio: Optional[str] = None
    school: Optional[str] = None
    age: Optional[int] = None
    language_preference: Language
    country_region: Optional[str] = None
    interests: List[Domain] = []
    interest_content_types: List[ContentType] = []  # 内容类型兴趣（「看看」兴趣设置）
    role: Optional[UserRole] = None
    is_admin: bool = False  # 管理员标记（前端据此决定是否显示审核入口/悬浮球）
    created_at: datetime
    following_count: int = 0  # 我关注的人数（关注功能，服务端填）
    follower_count: int = 0   # 我的粉丝数
    favorite_count: int = 0   # 我收藏的项目数（收藏 Tab 计数）
    received_like_count: int = 0  # 我的内容获赞总数（我的项目反应 + 我的动态点赞）


class MeUpdate(BaseModel):
    """PATCH /me：只传想改的字段。"""

    nickname: Optional[str] = Field(None, min_length=1, max_length=50)
    handle: Optional[str] = Field(None, min_length=3, max_length=30)  # @handle，唯一，校验在 me.update
    avatar_url: Optional[str] = None
    bio: Optional[str] = Field(None, max_length=500)
    school: Optional[str] = Field(None, max_length=100)
    age: Optional[int] = Field(None, ge=1, le=120)
    language_preference: Optional[Language] = None
    country_region: Optional[str] = Field(None, max_length=50)
    interests: Optional[List[Domain]] = None
    interest_content_types: Optional[List[ContentType]] = None
    role: Optional[UserRole] = None


class InterestsWrite(BaseModel):
    """POST /me/interests：onboarding 写入（可跳过，跳过就不调）。"""

    interests: List[Domain] = Field(min_length=1, description="至少选 1 个领域")


class PushPreferencesResponse(BaseModel):
    daily_pick_enabled: bool
    weekly_ranking_enabled: bool
    how_to_interest_enabled: bool  # 语义=想试/want_to_try（列名保留）
    similar_project_enabled: bool
    content_status_enabled: bool
    system_enabled: bool
    interaction_enabled: bool


class PushPreferencesUpdate(BaseModel):
    """PATCH /me/push-preferences：只传想改的开关。"""

    daily_pick_enabled: Optional[bool] = None
    weekly_ranking_enabled: Optional[bool] = None
    how_to_interest_enabled: Optional[bool] = None  # 语义=想试
    similar_project_enabled: Optional[bool] = None
    content_status_enabled: Optional[bool] = None
    system_enabled: Optional[bool] = None
    interaction_enabled: Optional[bool] = None


class UserBrief(BaseModel):
    """嵌在项目里的作者信息（卡片/详情用）。"""

    id: uuid.UUID
    handle: Optional[str] = None  # 稳定用户名 @handle
    nickname: Optional[str] = None
    avatar_url: Optional[str] = None
    role: Optional[UserRole] = None


class UserPublic(UserBrief):
    """GET /users/{id}：用户主页（页面地图要求"作者头像→用户主页→其作品"）。"""

    bio: Optional[str] = None
    school: Optional[str] = None
    age: Optional[int] = None
    published_project_count: int = 0
    following_count: int = 0
    follower_count: int = 0
    is_followed_by_me: bool = False  # 登录时=当前用户是否已关注 ta；游客=false
