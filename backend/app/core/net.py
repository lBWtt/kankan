# ============================================================
# 这个文件是干什么的：从请求里安全地取「真实来源 IP」——供按 IP 限流用。
# 它对应产品里的什么功能：登录发码 / 埋点的 IP 级频控（防 SMS pumping / 刷埋点）。
# 如果它出错了：要么把反代后所有用户误当同一 IP 限死，要么信了伪造的 XFF 让 IP 限流被绕过。
# ============================================================
from __future__ import annotations

from fastapi import Request

from app.core.config import settings


def client_ip(request: Request) -> str:
    """取真实来源 IP（仅用于按 IP 限流，非鉴权）。

    安全要点：X-Forwarded-For 是客户端可任意伪造的请求头。只有当我方确实部署在
    N 层可信反代之后（settings.trusted_proxy_hops = N）时才信任它，且取「从右数第 N 个」
    ——可信反代会把它看到的真实对端追加在 XFF 最右，客户端预先塞的伪造值都在左侧，直接忽略。

    未配反代（hops=0，默认）时完全忽略 XFF，用 socket 对端 IP（request.client.host，不可伪造）。
    这样：直连部署防伪造；反代部署（正确设 hops）既拿到真实客户端 IP、又不被换头绕过。
    """
    hops = settings.trusted_proxy_hops
    if hops > 0:
        xff = request.headers.get("x-forwarded-for")
        if xff:
            parts = [p.strip() for p in xff.split(",") if p.strip()]
            if len(parts) >= hops:
                return parts[-hops]
            # XFF 段数比声明的可信层数还少（被人裁剪/异常）→ 不猜，退回不可伪造的对端 IP。
    return request.client.host if request.client else "unknown"
