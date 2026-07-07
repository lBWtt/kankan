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
from app.core.errors import AppError, app_error_handler, validation_error_handler
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

app.include_router(api_v1_router)

# 上传文件的静态托管（V0 本地盘；生产换对象存储后撤掉）
os.makedirs(settings.upload_dir, exist_ok=True)
app.mount("/uploads", StaticFiles(directory=settings.upload_dir), name="uploads")


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
