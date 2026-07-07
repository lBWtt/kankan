# ============================================================
# 这个文件是干什么的：后端和 Redis（高速缓存）之间的连接——验证码的临时存放、
#   发送频控，将来还有热门榜单的实时分数。
# 它对应产品里的什么功能：登录验证码的 5 分钟有效期和 60 秒重发限制；后续的本周热门榜。
# 如果它出错了，用户会看到什么现象：收不到/对不上验证码导致登录不了；榜单退化为实时计算变慢。
# ============================================================
from redis import Redis

from app.core.config import settings

# socket_connect_timeout/socket_timeout=2s：慢/挂的 Redis 不能让 FastAPI threadpool
#   （40 线程）被并发认证请求吃光——否则整个服务连同 /health 一起卡死。
# retry_on_timeout + retry_on_error：瞬时抖动自动重试一次，减少 503。
# health_check_interval=30s：长连接定期自检，及时发现被中间设备掐断的半死连接。
redis_client = Redis.from_url(
    settings.redis_url,
    decode_responses=True,
    socket_connect_timeout=2,
    socket_timeout=2,
    retry_on_timeout=True,
    retry_on_error=[ConnectionError, TimeoutError],
    health_check_interval=30,
)
