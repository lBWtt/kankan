# ============================================================
# 这个文件是干什么的：v1 接口的"总装配线"——把各模块的路由汇成一个 /api/v1 路由器。
# 它对应产品里的什么功能：所有接口的统一前缀和分组；/docs 文档页的目录结构。
# 如果它出错了，用户会看到什么现象：部分或全部接口 404。
# ============================================================
from fastapi import APIRouter

from app.api.v1 import (
    admin,
    auth,
    comments,
    events,
    feedback,
    me,
    media,
    notifications,
    posts,
    project_actions,
    projects,
    rankings,
    topics,
    users,
)

api_v1_router = APIRouter(prefix="/api/v1")

api_v1_router.include_router(auth.router)
api_v1_router.include_router(me.router)
api_v1_router.include_router(projects.router)
api_v1_router.include_router(project_actions.router)
api_v1_router.include_router(rankings.router)
api_v1_router.include_router(notifications.router)
api_v1_router.include_router(users.router)
api_v1_router.include_router(media.router)
api_v1_router.include_router(events.router)
api_v1_router.include_router(comments.router)
api_v1_router.include_router(posts.router)
api_v1_router.include_router(topics.router)
api_v1_router.include_router(feedback.router)
api_v1_router.include_router(admin.router)
