# ============================================================
# 这个文件是干什么的：AI 整理的「成本护栏」——每天最多调用多少次 DeepSeek/Claude，跨进程用 Redis 计数。
# 它对应产品里的什么功能：定时/批量抓取整理时，防止一波洪峰把 AI 账单打爆。
# 如果它出错了：要么整理被误挡（超额判断错），要么护栏失效（Redis 挂时放行——这是有意的 fail-open）。
# 设计取舍：Redis 不可用时 fail-open（放行）——单批仍有 limit 兜底，护栏抖动不该卡死整条流水线。
# ============================================================
import logging
from datetime import date
from typing import Optional

from app.core.config import settings
from app.core.redis import redis_client

logger = logging.getLogger("app.ai_budget")

# 跨天兜底 TTL：36h 覆盖任何时区/跨天边界，键自然过期不残留。
_TTL_SECONDS = 36 * 60 * 60


def _key() -> str:
    return f"ai:daily_calls:{date.today().isoformat()}"


def budget_remaining() -> Optional[int]:
    """当日剩余可调用次数。cap<=0（不限）或 Redis 不可用时返回 None（视为不限）。"""
    cap = settings.ai_daily_call_cap
    if cap <= 0:
        return None
    try:
        used = int(redis_client.get(_key()) or 0)
    except Exception:
        logger.warning("ai budget: redis 不可用，剩余额度按不限处理（fail-open）")
        return None
    return max(0, cap - used)


def try_consume(n: int = 1) -> bool:
    """预占 n 次调用配额：够用→True 并计数；超额→False（触发降级=停整理）。
    Redis 不可用 → True（fail-open，靠单批 limit 兜底）。"""
    cap = settings.ai_daily_call_cap
    if cap <= 0:
        return True
    try:
        key = _key()
        used = redis_client.incr(key, n)
        if used == n:  # 本键今天首次创建 → 设过期
            redis_client.expire(key, _TTL_SECONDS)
        if used > cap:
            # 超额：回滚这次预占，让计数停在 cap 上，别把数字越堆越高
            redis_client.decrby(key, n)
            logger.warning("ai budget: 当日调用已达上限 %s，本批停整理", cap)
            return False
        return True
    except Exception:
        logger.warning("ai budget: redis 不可用，放行本次调用（fail-open）")
        return True
