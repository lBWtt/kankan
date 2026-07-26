# ============================================================
# 这个文件是干什么的：后端服务的"大门"——启动 FastAPI 应用，挂上全部 v1 接口
#   和统一报错格式。54 个契约端点已全部实现（V0 内容链路→V1 主信号→V2 发布→V3 后台管理）。
# 它对应产品里的什么功能：所有接口的入口；/docs 是前后端对齐用的可交互契约文档。
# 如果它出错了，用户会看到什么现象：整个后端起不来，App 所有联网功能瘫痪。
# ============================================================
import asyncio
import logging
import os
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from sqlalchemy import text

from app.api.v1 import api_v1_router
from app.core.config import settings, validate_production_settings
from app.core.db import engine
from app.core.errors import (
    AppError,
    app_error_handler,
    unhandled_exception_handler,
    validation_error_handler,
)
from app.core.redis import redis_client
from app.services.maintenance import start_scheduler

logger = logging.getLogger("app.main")


@asynccontextmanager
async def lifespan(_: FastAPI):
    # 生产配置自检：致命问题（默认密钥/无短信商）直接拒绝启动，警告写日志
    for warning in validate_production_settings():
        logger.warning("生产配置警告：%s", warning)
    # CORS 配置自检：生产环境不应使用默认 localhost origins
    cors_origins = os.getenv("CORS_ALLOW_ORIGINS", "")
    if not cors_origins and settings.app_env == "prod":
        logger.warning("生产环境未配置 CORS_ALLOW_ORIGINS，使用默认 localhost origins 可能不安全")
    # 定时任务随服务启动：榜单每小时刷新 + 每日 00:10 全量校准与媒体回收
    tasks = start_scheduler()
    yield
    for t in tasks:
        t.cancel()
    # 等待取消真正完成，避免任务在退出时仍持有 DB 会话/连接造成告警或资源泄漏
    await asyncio.gather(*tasks, return_exceptions=True)


app = FastAPI(
    lifespan=lifespan,
    title="AI 创意项目发现 App — Backend",
    version="1.0.0",
    description=(
        "API 契约 v1.0（对齐 字段·API v1.3 §6-9），54 个端点全部已实现。\n\n"
        "- 错误结构统一为 {code, message, details}，错误码清单见 docs/API契约_v1.0.md\n"
        "- 列表统一游标分页：cursor + page_size（默认 20，上限 50）\n"
        "- 带锁图标的接口需登录（JWT Bearer）；想看怎么做/分享/浏览对游客开放"
    ),
)

# CORS：web 端（Flutter build web）从浏览器跨域调用需要放行来源。
# 默认放行本机 web 开发端口；生产用环境变量 CORS_ALLOW_ORIGINS（逗号分隔）覆盖。
_cors_origins = [
    o.strip()
    for o in os.getenv(
        "CORS_ALLOW_ORIGINS",
        "http://localhost:5599,http://127.0.0.1:5599,"
        "http://localhost:8080,http://127.0.0.1:8080",
    ).split(",")
    if o.strip()
]
app.add_middleware(
    CORSMiddleware,
    allow_origins=_cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.add_exception_handler(AppError, app_error_handler)
app.add_exception_handler(RequestValidationError, validation_error_handler)
# 兜底：未捕获异常统一转 {code,message,details}，RedisError 单独走 503，避免破坏响应契约
app.add_exception_handler(Exception, unhandled_exception_handler)

app.include_router(api_v1_router)

# 上传文件的静态托管（V0 本地盘；生产换对象存储后撤掉）
os.makedirs(settings.upload_dir, exist_ok=True)
app.mount("/uploads", StaticFiles(directory=settings.upload_dir), name="uploads")

# 内部内容审核台（Web）：纯静态单页，同源托管，只调 /api/v1/admin/* 现成接口。
# 单独做成网页而非塞进 App——审核是运营工具，不该跟着用户包发出去（安全 + 迭代节奏）。
# 打开 http://<host>/admin-web/ ；接口本身有 admin_required 兜底，页面可见不等于可操作。
# 生产默认关闭：dev 下默认挂出方便本地审核；非 dev（prod）默认**不挂**，必须显式
# ADMIN_WEB_ENABLED=1 才挂——避免"忘了关"让审核台公网可见（接口有 admin_required 兜底，
# 但页面本身不该裸露）。要在生产开放，请配合 IP 白名单/内网/Cloudflare Access。
_admin_web_dir = os.path.join(os.path.dirname(os.path.dirname(__file__)), "admin_web")
_admin_web_default = "1" if settings.app_env == "dev" else "0"
if os.getenv("ADMIN_WEB_ENABLED", _admin_web_default) == "1" and os.path.isdir(_admin_web_dir):
    app.mount("/admin-web", StaticFiles(directory=_admin_web_dir, html=True), name="admin-web")


@app.get("/health", tags=["运维"])
def health():
    """健康检查：返回 200 即服务存活。"""
    return {"status": "ok"}


@app.get("/health/detailed", tags=["运维"])
def health_detailed():
    """详细健康检查：验证数据库和 Redis 连接状态。
    用于监控发现依赖服务故障，而非心跳。"""
    db_ok = True
    redis_ok = True
    try:
        # 测试数据库连接（SQLAlchemy 2.x execute 必须用 text() 包装裸 SQL，否则抛 ObjectNotExecutableError）
        with engine.connect() as conn:
            conn.execute(text("SELECT 1"))
    except Exception as e:
        logger.error("数据库连接异常：%s", e)
        db_ok = False

    try:
        # 测试 Redis 连接
        redis_client.ping()
    except Exception as e:
        logger.error("Redis 连接异常：%s", e)
        redis_ok = False

    status = "ok" if db_ok and redis_ok else "degraded"
    return {
        "status": status,
        "database": "ok" if db_ok else "error",
        "redis": "ok" if redis_ok else "error",
    }
