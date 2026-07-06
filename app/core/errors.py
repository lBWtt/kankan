# ============================================================
# 这个文件是干什么的：定义全后端统一的"报错格式"——任何接口出错都返回
#   code/message/details 三件套（字段·API v1.3 §6），并集中列出所有错误码。
# 它对应产品里的什么功能：所有接口的错误提示；App 靠 code 决定弹什么提示、要不要跳登录。
# 如果它出错了，用户会看到什么现象：报错提示混乱或前端无法识别错误原因，
#   比如该弹登录框的地方弹了"系统错误"。
# ============================================================
from typing import Optional

from fastapi import Request
from fastapi.encoders import jsonable_encoder
from fastapi.responses import JSONResponse


class AppError(Exception):
    """业务错误基类：抛出后由全局 handler 统一转成 {code, message, details}。"""

    def __init__(self, status_code: int, code: str, message: str, details: Optional[dict] = None):
        self.status_code = status_code
        self.code = code
        self.message = message
        self.details = details


# ---- 通用错误码（HTTP 状态码 → code）----
# 401 AUTH_REQUIRED        需登录（前端应弹登录框，成功后重试原动作）
# 403 FORBIDDEN            无权限（如非管理员调后台接口、改别人的项目）
# 404 NOT_FOUND            资源不存在或已删除
# 409 ALREADY_EXISTS       重复动作（如重复收藏、重复订阅）
# 422 VALIDATION_FAILED    参数校验失败（FastAPI 自动校验也归一成此结构）
# 429 RATE_LIMITED         频控（如验证码发送过频）
# 500 INTERNAL             服务器内部错误
# 501 NOT_IMPLEMENTED      契约已定义、实现排期中（本阶段所有业务接口）
#
# ---- 业务错误码 ----
# 409 PUBLISH_GATE_FAILED      发布准入不满足：tools≥1 或简介含可复现说明（PRD §2.3 红线）
# 409 HOW_TO_DISABLED          该项目关闭了"想看怎么做"（allow_how_to_interest=false）
# 409 CANDIDATE_INVALID_STATE  候选状态不允许该操作（如对 discarded 执行 approve）
# 409 PROJECT_INVALID_STATE    项目状态不允许该管理动作（如对 deleted 执行 take-down）
# 422 ANON_ID_REQUIRED         游客触发想看怎么做/分享时必须带 anon_client_id


def not_implemented() -> AppError:
    """契约阶段所有业务接口的统一占位：501 + 明确说明。"""
    return AppError(501, "NOT_IMPLEMENTED", "接口契约已定义，实现排期中（见 docs/API契约_v1.0.md）")


async def app_error_handler(request: Request, exc: AppError) -> JSONResponse:
    return JSONResponse(
        status_code=exc.status_code,
        content={"code": exc.code, "message": exc.message, "details": exc.details},
    )


async def validation_error_handler(request: Request, exc) -> JSONResponse:
    """把 FastAPI 自动参数校验的报错也归一成 code/message/details 结构。
    errors() 里可能嵌着原始异常对象（如模型校验器抛的 ValueError），必须先转成可序列化的结构，
    否则 422 会变成 500。"""
    safe_errors = jsonable_encoder(exc.errors(), custom_encoder={Exception: str})
    return JSONResponse(
        status_code=422,
        content={"code": "VALIDATION_FAILED", "message": "参数校验失败", "details": {"errors": safe_errors}},
    )
