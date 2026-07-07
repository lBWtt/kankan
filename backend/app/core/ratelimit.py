# ============================================================
# 这个文件是干什么的：通用 Redis 限流工具（固定窗口）——供 API 层给任意端点加频控。
# 它对应产品里的什么功能：登录验证码发送频控、敏感操作（点赞/评论/关注）防刷、
#   AI 抓取触发频控等。API 层只需一行 rate_limit(key, limit, window) 即可。
# 如果它出错了，用户会看到什么现象：频控失效（刷接口）或反过来把正常用户挡在外面。
# ============================================================
"""
通用 Redis 限流工具（固定窗口）。
供 API 层调用：rate_limit("send_code:ip:1.2.3.4", limit=10, window=3600)
"""
from __future__ import annotations

import logging

from app.core.errors import AppError
from app.core.redis import redis_client

logger = logging.getLogger("app.ratelimit")


def rate_limit(key: str, limit: int, window: int) -> None:
    """
    固定窗口限流。超过 limit 抛 AppError(429)。
    Redis 不可用时 fail-open（放行，只记日志），避免拖垮主流程——
    频控是保护性措施，宁可短暂失效也不能让 Redis 抖动把登录/发布等核心功能打挂。
    """
    try:
        current = redis_client.incr(key)
        if current == 1:
            redis_client.expire(key, window)
        if current > limit:
            raise AppError(429, "RATE_LIMITED", "请求过于频繁，请稍后再试")
    except AppError:
        raise
    except Exception as exc:
        logger.warning("限流检查失败（fail-open）：%s", exc)
