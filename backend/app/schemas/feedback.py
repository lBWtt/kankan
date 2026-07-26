# ============================================================
# 这个文件是干什么的：意见反馈的请求/响应模型——用户提交反馈、后台列表展示。
# 它对应产品里的什么功能：设置/我的页「意见反馈」入口、后台反馈队列。
# ============================================================
import uuid
from datetime import datetime
from enum import Enum
from typing import Optional

from pydantic import BaseModel, Field


class FeedbackCategory(str, Enum):
    bug = "bug"
    suggestion = "suggestion"
    other = "other"


class FeedbackCreate(BaseModel):
    category: FeedbackCategory = FeedbackCategory.bug
    content: str = Field(min_length=1, max_length=2000, description="反馈正文")
    contact: Optional[str] = Field(None, max_length=100, description="选填联系方式")
    # 客户端自动带上的排障信息（用户无需填）
    app_version: Optional[str] = Field(None, max_length=40)
    platform: Optional[str] = Field(None, max_length=20)
    device_info: Optional[str] = Field(None, max_length=200)
    source_page: Optional[str] = Field(None, max_length=120)
    error_code: Optional[str] = Field(None, max_length=80)


class FeedbackAccepted(BaseModel):
    ok: bool = True
    id: uuid.UUID


class AdminFeedbackItem(BaseModel):
    id: uuid.UUID
    category: str
    content: str
    contact: Optional[str] = None
    app_version: Optional[str] = None
    platform: Optional[str] = None
    device_info: Optional[str] = None
    source_page: Optional[str] = None
    error_code: Optional[str] = None
    status: str
    user_id: Optional[uuid.UUID] = None
    user_nickname: Optional[str] = None
    admin_note: Optional[str] = None
    created_at: datetime

    model_config = {"from_attributes": True}


class AdminFeedbackHandleRequest(BaseModel):
    note: Optional[str] = Field(None, max_length=1000)
