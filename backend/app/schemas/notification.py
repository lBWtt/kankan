# ============================================================
# 这个文件是干什么的：定义通知中心接口的数据形状——通知列表项和已读标记。
# 它对应产品里的什么功能：通知中心；点开落点规则：普通通知→详情页，clue_update→实现线索页。
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
        None, description="落点项目；type=clue_update 时客户端跳实现线索页，其余跳详情页"
    )
    is_read: bool
    created_at: datetime
