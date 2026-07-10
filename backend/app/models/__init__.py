# ============================================================
# 这个文件是干什么的：模型的"花名册"——把 26 张表的定义集中导出，
#   保证建库工具（Alembic）和业务代码都能一次性看到全部表。
# 它对应产品里的什么功能：不对应单一功能，是所有表被正确创建的前提。
# 如果它出错了，用户会看到什么现象：某些表悄悄没建出来，相关功能（如收藏、通知）整体报错。
# ============================================================
from app.models.base import Base
from app.models.user import User
from app.models.project import Project
from app.models.project_action import ProjectAction, ProjectActionEvent
from app.models.media import ProjectMedia
from app.models.tag import ProjectTag, ProjectTagRelation
from app.models.interaction import (
    ClueSubscription,
    Favorite,
    HowToInterest,
    ProjectReaction,
    SimilarProjectLink,
    TryItem,
    UserFollow,
)
from app.models.comment import Comment, CommentLike
from app.models.post import Post, PostLike, PostMedia
from app.models.share import Share
from app.models.report import Report
from app.models.notification import Notification, PushPreference
from app.models.candidate import CandidateContent
from app.models.admin_action import AdminAction
from app.models.analytics import AnalyticsEvent

__all__ = [
    "Base",
    "User",
    "Project",
    "ProjectAction",
    "ProjectActionEvent",
    "ProjectMedia",
    "ProjectTag",
    "ProjectTagRelation",
    "Favorite",
    "TryItem",
    "HowToInterest",
    "ClueSubscription",
    "SimilarProjectLink",
    "ProjectReaction",
    "UserFollow",
    "Comment",
    "CommentLike",
    "Post",
    "PostMedia",
    "PostLike",
    "Share",
    "Report",
    "Notification",
    "PushPreference",
    "CandidateContent",
    "AdminAction",
    "AnalyticsEvent",
]
