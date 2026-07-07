# ============================================================
# 这个文件是干什么的：接口的"门卫"——真实校验 JWT 令牌、查出当前用户，
#   并区分三档：需登录、游客可用（登录态可增强）、需管理员。
# 它对应产品里的什么功能：登录拦截规则（收藏/发布/举报需登录；浏览/想看怎么做/分享游客可用；
#   后台需管理员）。
# 如果它出错了，用户会看到什么现象：该拦的不拦（别人能动你的账号）或不该拦的拦了
#   （游客点想看怎么做被要求登录——这违反红线）。
# ============================================================
from typing import Optional

from fastapi import Depends, Security
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from app.core.db import get_db
from app.core.errors import AppError
from app.core.security import decode_token
from app.models import User
from app.schemas.common import ErrorResponse

_bearer = HTTPBearer(auto_error=False, description="JWT access token（POST /auth/login 获取）")


def _load_user(db: Session, token: str) -> User:
    user_id = decode_token(token, expected_type="access")
    user = db.get(User, user_id)
    if user is None or user.deleted_at is not None:
        raise AppError(401, "AUTH_REQUIRED", "账号不存在或已注销")
    return user


def auth_required(
    db: Session = Depends(get_db),
    credentials: Optional[HTTPAuthorizationCredentials] = Security(_bearer),
) -> User:
    """需登录的接口挂这个：无 token / token 失效 → 401 AUTH_REQUIRED（前端弹登录后重试原动作）。"""
    if credentials is None:
        raise AppError(401, "AUTH_REQUIRED", "请先登录")
    return _load_user(db, credentials.credentials)


def auth_optional(
    db: Session = Depends(get_db),
    credentials: Optional[HTTPAuthorizationCredentials] = Security(_bearer),
) -> Optional[User]:
    """游客可用的接口挂这个：没带 token = 游客（返回 None）；带了坏 token 仍然 401（明确报错，不静默降级）。"""
    if credentials is None:
        return None
    return _load_user(db, credentials.credentials)


def admin_required(user: User = Depends(auth_required)) -> User:
    """后台接口挂这个：已登录但不是管理员 → 403 FORBIDDEN。"""
    if not user.is_admin:
        raise AppError(403, "FORBIDDEN", "需要管理员权限")
    return user


# 路由器级别的错误响应文档（挂在 APIRouter(responses=...) 上，让 /docs 显示错误契约）
ERRORS_AUTHED = {
    401: {"model": ErrorResponse, "description": "未登录（AUTH_REQUIRED）"},
    403: {"model": ErrorResponse, "description": "无权限（FORBIDDEN)"},
    404: {"model": ErrorResponse, "description": "资源不存在（NOT_FOUND）"},
    501: {"model": ErrorResponse, "description": "契约已定义，实现排期中（NOT_IMPLEMENTED）"},
}
ERRORS_PUBLIC = {
    404: {"model": ErrorResponse, "description": "资源不存在（NOT_FOUND）"},
    501: {"model": ErrorResponse, "description": "契约已定义，实现排期中（NOT_IMPLEMENTED）"},
}
