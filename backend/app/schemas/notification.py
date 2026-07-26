# ============================================================
# 这个文件是干什么的：定义通知中心接口的数据形状——通知列表项和已读标记。
# 它对应产品里的什么功能：通知中心；点开落点规则：普通通知→详情页，want_to_try→「想试的人」页。
# 如果它出错了，用户会看到什么现象：通知中心空白或点开跳错页面，红点消不掉。
# ============================================================
import uuid
from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field

from app.schemas.common import NotificationType


class NotificationItem(BaseModel):
    id: uuid.UUID
    type: NotificationType
    title: str
    body: Optional[str] = None
    project_id: Optional[uuid.UUID] = Field(
        None, description="落点项目；type=want_to_try 时客户端跳「想试的人」页，其余跳详情页"
    )
    # 互动通知深链（关注/动态点赞/动态评论）：actor=触发者（跳 ta 主页 + 显头像）、post=动态落点。
    actor_user_id: Optional[uuid.UUID] = None
    post_id: Optional[uuid.UUID] = None
    is_read: bool
    created_at: datetime
