# ============================================================
# 这个文件是干什么的：公共工具函数——游标解析、LIKE 转义、日志等跨模块复用逻辑。
# 它对应产品里的什么功能：不对应单一功能，是代码复用的基础设施。
# 如果它出错了，用户会看到什么现象：分页异常、搜索结果不准确。
# ============================================================
from __future__ import annotations

import uuid
import logging
from datetime import datetime

from app.core.errors import AppError
from app.core.pagination import decode_cursor

logger = logging.getLogger("kankan")

# ---- 游标解析工具 ----


def parse_datetime_cursor(cursor: str) -> tuple[datetime, uuid.UUID]:
    """解析 datetime+UUID 游标，统一错误处理。
    用法：c_dt, c_id = parse_datetime_cursor(cursor)
    """
    dt_s, id_s = decode_cursor(cursor, 2)
    try:
        c_dt = datetime.fromisoformat(dt_s)
        c_id = uuid.UUID(id_s)
    except ValueError:
        raise AppError(422, "VALIDATION_FAILED", "cursor 无效")
    return c_dt, c_id


# ---- LIKE 搜索转义 ----


def escape_like_pattern(s: str) -> str:
    """转义 SQL LIKE 特殊字符 % 和 _，防止模式注入。
    用户输入 % 或 _ 可能导致意外匹配（如 % 匹配任意字符）。
    """
    return s.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")


def safe_like_pattern(q: str) -> str:
    """构建安全的 LIKE 模式字符串，已转义特殊字符。
    用法：stmt = stmt.where(Project.title.ilike(safe_like_pattern(q)))
    """
    return f"%{escape_like_pattern(q)}%"


# ---- 业务日志工具 ----


def log_business(action: str, user_id: uuid.UUID | None, **kwargs) -> None:
    """结构化业务日志，方便问题排查。
    用法：log_business("收藏项目", user.id, project_id=project_id)
    """
    details = {k: str(v) for k, v in kwargs.items()}
    if user_id:
        logger.info("[业务] %s | user=%s | %s", action, user_id, details)
    else:
        logger.info("[业务] %s | anonymous | %s", action, details)