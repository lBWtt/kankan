# ============================================================
# 这个文件是干什么的：登录相关接口的路由——发验证码、验证码登录（未注册自动注册）、刷新令牌。
# 它对应产品里的什么功能：登录弹窗；被拦截动作（收藏/发布等）触发，成功后回到原动作。
# 如果它出错了，用户会看到什么现象：登录不上，所有需要账号的功能都无法使用。
# ============================================================
import re
import secrets

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.deps import ERRORS_PUBLIC
from app.core.config import dev_login_enabled
from app.core.db import get_db
from app.core.errors import AppError
from app.core.redis import redis_client
from app.core.security import create_token_pair, rotate_refresh_token
from app.models import HowToInterest, User
from app.schemas.auth import LoginRequest, LoginResponse, RefreshRequest, SendCodeRequest, TokenPair
from app.schemas.common import OkResponse
from app.schemas.user import MeResponse
from app.services.sms import generate_code, send_login_code

router = APIRouter(prefix="/auth", tags=["认证"], responses=ERRORS_PUBLIC)

CODE_TTL_SECONDS = 300       # 验证码 5 分钟有效
RESEND_INTERVAL_SECONDS = 60  # 同一标识 60 秒只能发一条
MAX_CODE_ATTEMPTS = 5         # 同一标识连续验证码错误上限，超出锁定（防 6 位码撞库）
CODE_ATTEMPT_WINDOW_SECONDS = 600  # 锁定/计数窗口 10 分钟
DEV_UNIVERSAL_CODE = "888888"  # 仅 dev 且 JWT 为默认密钥时接受（见 config.dev_login_enabled）

_EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
_PHONE_RE = re.compile(r"^\+?\d{5,20}$")


def _validate_identifier(identifier_type: str, identifier: str) -> None:
    pattern = _EMAIL_RE if identifier_type == "email" else _PHONE_RE
    if not pattern.match(identifier):
        raise AppError(422, "VALIDATION_FAILED", "手机号或邮箱格式不正确", {"identifier": identifier})


def _merge_anon_records(db: Session, user: User, anon_client_id: str) -> None:
    """把游客身份记的想看怎么做归并进账号：账号已有同项目记录的先删游客行（防撞唯一索引），
    其余游客行改挂到账号上。"""
    guest_rows = db.scalars(
        select(HowToInterest).where(
            HowToInterest.anon_client_id == anon_client_id, HowToInterest.user_id.is_(None)
        )
    ).all()
    if not guest_rows:
        return
    owned_project_ids = set(
        db.scalars(select(HowToInterest.project_id).where(HowToInterest.user_id == user.id)).all()
    )
    for row in guest_rows:
        if row.project_id in owned_project_ids:
            db.delete(row)
        else:
            row.user_id = user.id
            row.anon_client_id = None


@router.post("/send-code", response_model=OkResponse, summary="发送验证码（补全端点）")
def send_code(body: SendCodeRequest):
    """频控：同一标识 60 秒 1 条；超限 429 RATE_LIMITED。
    发送走 services/sms.py：console=只写日志（开发），aliyun=真发短信；发送失败 500 且验证码作废。"""
    _validate_identifier(body.identifier_type.value, body.identifier)
    rl_key = f"authcode:rl:{body.identifier_type.value}:{body.identifier}"
    if redis_client.exists(rl_key):
        raise AppError(429, "RATE_LIMITED", "发送太频繁，请 60 秒后再试")
    code = generate_code()
    code_key = f"authcode:{body.identifier_type.value}:{body.identifier}"
    redis_client.setex(code_key, CODE_TTL_SECONDS, code)
    redis_client.setex(rl_key, RESEND_INTERVAL_SECONDS, "1")
    try:
        send_login_code(body.identifier_type.value, body.identifier, code)
    except AppError:
        redis_client.delete(code_key)  # 没发出去的码不留着，防止状态混乱
        raise
    return OkResponse()


@router.post("/login", response_model=LoginResponse, summary="验证码登录（未注册自动注册）")
def login(body: LoginRequest, db: Session = Depends(get_db)):
    """验证码错误/过期 → 422。带 anon_client_id 时归并游客的想看怎么做记录（红线主信号不丢）。"""
    _validate_identifier(body.identifier_type.value, body.identifier)
    code_key = f"authcode:{body.identifier_type.value}:{body.identifier}"
    fail_key = f"authfail:{body.identifier_type.value}:{body.identifier}"

    # 猜码次数锁：连续错够上限就拦下，不再给继续撞库的机会（6 位码穷举防护）
    if int(redis_client.get(fail_key) or 0) >= MAX_CODE_ATTEMPTS:
        raise AppError(429, "RATE_LIMITED", "验证码尝试次数过多，请 10 分钟后再试")

    stored = redis_client.get(code_key)
    dev_ok = dev_login_enabled() and body.code == DEV_UNIVERSAL_CODE
    if not dev_ok and (stored is None or stored != body.code):
        attempts = redis_client.incr(fail_key)
        if attempts == 1:  # 首次失败才设窗口，之后累加不续期（固定 10 分钟窗口）
            redis_client.expire(fail_key, CODE_ATTEMPT_WINDOW_SECONDS)
        raise AppError(422, "VALIDATION_FAILED", "验证码错误或已过期")
    redis_client.delete(code_key)
    redis_client.delete(fail_key)  # 登录成功清空失败计数

    field = User.email if body.identifier_type.value == "email" else User.phone
    user = db.scalar(select(User).where(field == body.identifier, User.deleted_at.is_(None)))
    is_new_user = user is None
    if is_new_user:
        user = User(
            email=body.identifier if body.identifier_type.value == "email" else None,
            phone=body.identifier if body.identifier_type.value == "phone" else None,
            nickname=f"创意客{secrets.randbelow(10000):04d}",
        )
        db.add(user)
        db.flush()

    if body.anon_client_id:
        _merge_anon_records(db, user, body.anon_client_id)

    db.commit()
    db.refresh(user)
    return LoginResponse(
        **create_token_pair(user.id),
        user=MeResponse.model_validate(user),
        is_new_user=is_new_user,
    )


@router.post("/refresh", response_model=TokenPair, summary="刷新令牌（补全端点）")
def refresh(body: RefreshRequest, db: Session = Depends(get_db)):
    """refresh_token 失效 → 401 AUTH_REQUIRED（前端清登录态）。每次刷新轮换双令牌：
    旧 refresh 的 jti 当场消费作废，被窃旧令牌无法在 30 天内反复续命。"""
    user_id = rotate_refresh_token(body.refresh_token)  # 校验 + 一次性消费旧 jti
    user = db.get(User, user_id)
    if user is None or user.deleted_at is not None:
        raise AppError(401, "AUTH_REQUIRED", "账号不存在或已注销")
    return TokenPair(**create_token_pair(user.id))
