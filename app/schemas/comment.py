# ============================================================
# 这个文件是干什么的：评论接口的数据形状——发评论请求、评论返回（含楼中楼 replies）。
# 它对应产品里的什么功能：项目/动态详情下的评论区。
# 如果它出错了，用户会看到什么现象：评论发不出或显示错位。
# ============================================================
import uuid
from datetime import datetime
from typing import List, Optional

from pydantic import BaseModel, Field

from app.schemas.user import UserBrief


class CommentCreate(BaseModel):
    """POST /comments：host_type∈{project,post}；parent_comment_id 回复顶级评论时带。"""

    host_type: str = Field(description="project | post")
    host_id: uuid.UUID
    content: str = Field(min_length=1, max_length=2000)
    parent_comment_id: Optional[uuid.UUID] = None


class CommentOut(BaseModel):
    """评论返回（对齐前端 Comment）：authorId 从 author.id 取；likes=like_count；
    replies 是内嵌数组，仅顶级评论带（子回复自身 replies 恒空）。"""

    id: uuid.UUID
    host_type: str
    host_id: uuid.UUID
    author: Optional[UserBrief] = None
    content: str
    likes: int = 0
    replies: List["CommentOut"] = []
    created_at: datetime
    is_liked: bool = False  # 登录时=当前用户是否已赞该评论；游客 false


CommentOut.model_rebuild()  # 解析自引用 List["CommentOut"]
