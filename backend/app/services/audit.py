# ============================================================
# 这个文件是干什么的：管理员操作留痕的统一入口——后台每个动作（通过/下架/删除…）
#   都经这里写一条 admin_actions 日志。
# 它对应产品里的什么功能：后台"操作日志"页；出问题（如误下架）时追责回溯。
# 如果它出错了，用户会看到什么现象：用户无感知，但运营操作无据可查。
# ============================================================
import uuid
from typing import Optional

from sqlalchemy.orm import Session

from app.models import AdminAction


def log_admin_action(
    db: Session,
    admin_user_id: uuid.UUID,
    action: str,
    target_type: str,
    target_id: Optional[uuid.UUID],
    detail: Optional[dict] = None,
) -> None:
    """只入会话不提交——和业务改动同一个事务，要成一起成、要败一起败。"""
    db.add(
        AdminAction(
            admin_user_id=admin_user_id,
            action=action,
            target_type=target_type,
            target_id=target_id,
            detail=detail,
        )
    )
