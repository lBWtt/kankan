# ============================================================
# 这个文件是干什么的：定义登录相关接口的数据形状——发验证码、验证码登录、刷新令牌。
# 它对应产品里的什么功能：登录弹窗（被拦截动作触发，成功后回到原动作）。
# 如果它出错了，用户会看到什么现象：登录不上，所有需要账号的动作（收藏/发布/订阅）都用不了。
# ============================================================
from enum import Enum
from typing import Optional

from pydantic import BaseModel, Field

from app.schemas.user import MeResponse


class IdentifierType(str, Enum):
    phone = "phone"
    email = "email"


class SendCodeRequest(BaseModel):
    """POST /auth/send-code（补全决策：字段文档只写了 login，验证码下发端点是必要补充）"""

    identifier_type: IdentifierType
    identifier: str = Field(max_length=255, description="手机号或邮箱")


class LoginRequest(BaseModel):
    """POST /auth/login：手机号/邮箱 + 验证码（字段·API v1.3 §7）。未注册则自动注册。"""

    identifier_type: IdentifierType
    identifier: str = Field(max_length=255)
    code: str = Field(min_length=4, max_length=8, description="验证码")
    anon_client_id: Optional[str] = Field(
        None, max_length=64, description="登录前的游客 ID；带上后服务端把游客的想看怎么做记录归并到账号"
    )


class TokenPair(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int = Field(description="access_token 有效秒数")


class LoginResponse(TokenPair):
    user: MeResponse
    is_new_user: bool = Field(description="true=本次登录自动注册了新账号（前端据此进 onboarding 兴趣采集）")


class RefreshRequest(BaseModel):
    """POST /auth/refresh（补全决策：§6 定了 JWT access+refresh，刷新端点是必要补充）"""

    refresh_token: str
