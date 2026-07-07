# ============================================================
# 这个文件是干什么的：动态接口的数据形状——发动态请求、动态返回。
# 它对应产品里的什么功能：发现页动态流、发动态、动态详情。
# 如果它出错了，用户会看到什么现象：动态发不出或显示错位。
# ============================================================
import uuid
from datetime import datetime
from typing import List, Optional

from pydantic import BaseModel, Field

from app.schemas.user import UserBrief


class PostCreate(BaseModel):
    """POST /posts：content 必填；media_ids 先调 POST /media 上传拿 id。"""

    content: str = Field(min_length=1, max_length=5000)
    tags: List[str] = Field(default=[])
    quote_project_id: Optional[uuid.UUID] = None
    media_ids: List[uuid.UUID] = Field(default=[])


class PostMediaOut(BaseModel):
    type: str  # image | video（对齐前端 MediaItem.type）
    url: str
    poster: Optional[str] = None


class PostOut(BaseModel):
    """动态返回（对齐前端 Post）：authorId 从 author.id；likes=like_count。"""

    id: uuid.UUID
    content: str
    author: Optional[UserBrief] = None
    media: List[PostMediaOut] = []
    tags: List[str] = []
    quote_project_id: Optional[uuid.UUID] = None
    likes: int = 0
    comment_count: int = 0
    created_at: datetime
    is_liked: bool = False  # 登录时=当前用户是否已赞；游客 false
