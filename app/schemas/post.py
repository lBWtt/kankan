# ============================================================
# 这个文件是干什么的：动态接口的数据形状——发动态请求、动态返回。
# 它对应产品里的什么功能：发现页动态流、发动态、动态详情。
# 如果它出错了，用户会看到什么现象：动态发不出或显示错位。
# ============================================================
import uuid
from datetime import datetime
from typing import List, Optional

from pydantic import BaseModel, Field, field_validator

from app.schemas.media import MediaType
from app.schemas.user import UserBrief


def _check_tag_items(v):
    """H-MDL-9：tags 元素长度校验（1-50 字符），供 PostCreate/ProjectCreate 复用。"""
    if v is None:
        return v
    for t in v:
        if not isinstance(t, str) or len(t) < 1 or len(t) > 50:
            raise ValueError("每个标签长度需在 1-50 之间")
    return v


class PostCreate(BaseModel):
    """POST /posts：content 必填；media_ids 先调 POST /media 上传拿 id。"""

    content: str = Field(min_length=1, max_length=5000)
    # H-MDL-9：tags 数量上限 20，元素长度 1-50
    tags: List[str] = Field(default=[], max_length=20)
    quote_project_id: Optional[uuid.UUID] = None
    # H-API-7：单条动态最多 9 张配图
    media_ids: List[uuid.UUID] = Field(default=[], max_length=9)

    @field_validator("tags", mode="after")
    @classmethod
    def _check_tag_len(cls, v):
        return _check_tag_items(v)


class PostMediaOut(BaseModel):
    # H-MDL-4：用 MediaType 枚举替代裸 str，与 schemas/project.MediaItem.media_type 保持一致
    type: MediaType
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
