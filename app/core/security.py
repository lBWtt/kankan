# ============================================================
# 这个文件是干什么的：登录令牌（JWT）的"印章车间"——签发和验证 access/refresh 两种令牌。
# 它对应产品里的什么功能：登录态的维持；App 每个需登录的请求都带着这里签发的令牌。
# 如果它出错了，用户会看到什么现象：登录后马上又被踢回登录页，或者令牌被伪造导致账号被冒用。
# ============================================================
import time
import uuid

import jwt

from app.core.config import settings
from app.core.errors import AppError
from app.core.redis import redis_client

ALGORITHM = "HS256"
# 刷新令牌白名单前缀：只有在册的 refresh jti 才能换新，换一次即从册上删除（一次性轮换+吊销）。
# 被窃的旧 refresh 一旦被合法端换过，就已失效，不能再无限续命 30 天。
REFRESH_ALLOWLIST_PREFIX = "refresh_jti:"


def _create_token(user_id: uuid.UUID, token_type: str, ttl_seconds: int) -> tuple:
    now = int(time.time())
    jti = uuid.uuid4().hex  # 唯一编号；refresh 令牌靠它进白名单做轮换吊销
    payload = {
        "sub": str(user_id),
        "type": token_type,       # access / refresh，防止两种令牌互相冒充
        "iat": now,
        "exp": now + ttl_seconds,
        "jti": jti,
    }
    return jwt.encode(payload, settings.jwt_secret, algorithm=ALGORITHM), jti


def create_token_pair(user_id: uuid.UUID) -> dict:
    """签发双令牌，并把 refresh 的 jti 登记进白名单（带与令牌一致的过期时间）。"""
    access, _ = _create_token(user_id, "access", settings.jwt_access_ttl_seconds)
    refresh, refresh_jti = _create_token(user_id, "refresh", settings.jwt_refresh_ttl_seconds)
    redis_client.setex(
        f"{REFRESH_ALLOWLIST_PREFIX}{refresh_jti}", settings.jwt_refresh_ttl_seconds, str(user_id)
    )
    return {
        "access_token": access,
        "refresh_token": refresh,
        "token_type": "bearer",
        "expires_in": settings.jwt_access_ttl_seconds,
    }


def _decode_payload(token: str, expected_type: str) -> dict:
    try:
        payload = jwt.decode(token, settings.jwt_secret, algorithms=[ALGORITHM])
    except jwt.ExpiredSignatureError:
        raise AppError(401, "AUTH_REQUIRED", "登录已过期，请重新登录")
    except jwt.InvalidTokenError:
        raise AppError(401, "AUTH_REQUIRED", "登录凭证无效")
    if payload.get("type") != expected_type:
        raise AppError(401, "AUTH_REQUIRED", "令牌类型不正确")
    return payload


def decode_token(token: str, expected_type: str) -> uuid.UUID:
    """验证令牌并取出用户 ID；任何问题（过期/伪造/类型不对）都抛 401 AUTH_REQUIRED。"""
    payload = _decode_payload(token, expected_type)
    try:
        return uuid.UUID(payload["sub"])
    except (KeyError, ValueError):
        raise AppError(401, "AUTH_REQUIRED", "登录凭证无效")


def rotate_refresh_token(token: str) -> uuid.UUID:
    """刷新专用：验证 refresh 令牌并**一次性消费**其 jti（从白名单删除），返回用户 ID。
    令牌伪造/过期/类型不对/已被用过或已吊销 → 401。调用方随后 create_token_pair 换发新令牌。"""
    payload = _decode_payload(token, "refresh")
    try:
        user_id = uuid.UUID(payload["sub"])
    except (KeyError, ValueError):
        raise AppError(401, "AUTH_REQUIRED", "登录凭证无效")
    jti = payload.get("jti")
    # delete 返回删掉的键数：1=在册且本次消费成功；0=不在册（已轮换/已吊销/旧版令牌）
    if not jti or redis_client.delete(f"{REFRESH_ALLOWLIST_PREFIX}{jti}") != 1:
        raise AppError(401, "AUTH_REQUIRED", "登录已失效，请重新登录")
    return user_id
