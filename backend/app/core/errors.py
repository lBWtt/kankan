# ============================================================
# 这个文件是干什么的：定义全后端统一的"报错格式"——任何接口出错都返回
#   code/message/details 三件套（字段·API v1.3 §6），并集中列出所有错误码。
# 它对应产品里的什么功能：所有接口的错误提示；App 靠 code 决定弹什么提示、要不要跳登录。
# 如果它出错了，用户会看到什么现象：报错提示混乱或前端无法识别错误原因，
#   比如该弹登录框的地方弹了"系统错误"。
# ============================================================
import logging
from typing import Optional

from fastapi import Request
from fastapi.encoders import jsonable_encoder
from fastapi.responses import JSONResponse
from redis.exceptions import RedisError

logger = logging.getLogger("app.errors")


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
# 503 DEPENDENCY_DOWN      依赖服务（Redis/DB）不可用，请稍后重试
#
# ---- 业务错误码 ----
# 409 PUBLISH_GATE_FAILED      发布准入不满足：tools≥1 或简介含足够说明（避免灌水）
# 409 HOW_TO_DISABLED          该项目关闭了"想试"（allow_how_to_interest=false；列名保留）
# 409 CANDIDATE_INVALID_STATE  候选状态不允许该操作（如对 discarded 执行 approve）
# 409 PROJECT_INVALID_STATE    项目状态不允许该管理动作（如对 deleted 执行 take-down）
# 422 ANON_ID_REQUIRED         游客触发想试/分享时必须带 anon_client_id



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


async def unhandled_exception_handler(request: Request, exc: Exception) -> JSONResponse:
    """兜底：所有未被 AppError / RequestValidationError handler 命中的异常都到这里，
    统一转成 {code, message, details}——否则 FastAPI 默认返回 {"detail":"Internal Server Error"}
    会破坏 errors.py 声明的响应契约，前端按 code 分支会直接失效。

    特殊处理 RedisError：依赖服务挂掉应返回 503 DEPENDENCY_DOWN（可重试），而非 500（不可恢复）。
    注意：本 handler 必须排在 AppError handler 之后注册——FastAPI 按"异常类型精确匹配"派发，
    AppError 是 Exception 子类，但精确匹配优先，所以 AppError 仍走 app_error_handler。
    """
    if isinstance(exc, RedisError):
        logger.exception("依赖服务异常")
        return JSONResponse(
            status_code=503,
            content={"code": "DEPENDENCY_DOWN", "message": "服务暂不可用，请稍后重试", "details": None},
        )
    logger.exception("未捕获异常")
    return JSONResponse(
        status_code=500,
        content={"code": "INTERNAL", "message": "服务器内部错误", "details": None},
    )
