# ============================================================
# 这个文件是干什么的：所有接口共用的"通用件"——枚举的接口版（从模型层唯一来源生成，
#   不二次定义值）、统一错误响应、游标分页信封、操作成功响应。
# 它对应产品里的什么功能：列表下拉加载（游标分页）、所有报错提示、所有下拉选项。
# 如果它出错了，用户会看到什么现象：列表翻页错乱或重复、报错格式前端无法解析。
# ============================================================
from enum import Enum
from typing import Generic, List, Optional, TypeVar

from pydantic import BaseModel, Field

from app.models import enums as model_enums


def _make_enum(name: str, values: tuple) -> type:
    """从 app/models/enums.py 的元组生成接口层枚举——保证枚举值全仓库只定义一处。"""
    return Enum(name, {v: v for v in values}, type=str)


Category = _make_enum("Category", model_enums.CATEGORY)
ContentType = _make_enum("ContentType", model_enums.CONTENT_TYPE)
Domain = _make_enum("Domain", model_enums.DOMAIN)
ProjectStatus = _make_enum("ProjectStatus", model_enums.PROJECT_STATUS)
CandidateStatus = _make_enum("CandidateStatus", model_enums.CANDIDATE_STATUS)
AiBadge = _make_enum("AiBadge", model_enums.AI_BADGE)
ContentSourceType = _make_enum("ContentSourceType", model_enums.CONTENT_SOURCE_TYPE)
ReactionType = _make_enum("ReactionType", model_enums.REACTION_TYPE)
ShareStatus = _make_enum("ShareStatus", model_enums.SHARE_STATUS)
ShareChannel = _make_enum("ShareChannel", model_enums.SHARE_CHANNEL)
NotificationType = _make_enum("NotificationType", model_enums.NOTIFICATION_TYPE)
ReportStatus = _make_enum("ReportStatus", model_enums.REPORT_STATUS)
Language = _make_enum("Language", model_enums.LANGUAGE)
UserRole = _make_enum("UserRole", model_enums.USER_ROLE)


class ErrorResponse(BaseModel):
    """统一错误结构（字段·API v1.3 §6）：所有非 2xx 响应都长这样。"""

    code: str = Field(description="机器可读错误码，见 app/core/errors.py 清单")
    message: str = Field(description="人类可读说明")
    details: Optional[dict] = Field(None, description="附加信息（如校验失败的具体字段）")


T = TypeVar("T")


class Page(BaseModel, Generic[T]):
    """游标分页信封（字段·API v1.3 §6）：cursor 是不透明字符串（服务端编码 published_at+id），
    客户端原样回传 next_cursor 取下一页；next_cursor 为 null 表示没有更多了。"""

    items: List[T]
    next_cursor: Optional[str] = None
    has_more: bool = False


class OkResponse(BaseModel):
    """无须返回数据的成功操作统一用这个。"""

    ok: bool = True
