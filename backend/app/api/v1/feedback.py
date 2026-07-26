# ============================================================
# 这个文件是干什么的：意见反馈提交接口——用户提 bug / 建议，落 feedbacks 表。
# 它对应产品里的什么功能：设置/我的页「意见反馈」入口。
# 如果它出错了，用户会看到什么现象：反馈提交失败（早期用户没法报 bug）。
# ============================================================
from typing import Optional

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.api.deps import ERRORS_PUBLIC, auth_optional
from app.core.db import get_db
from app.models import Feedback, User
from app.schemas.feedback import FeedbackAccepted, FeedbackCreate

router = APIRouter(prefix="/feedback", tags=["反馈"], responses=ERRORS_PUBLIC)


@router.post("", response_model=FeedbackAccepted, status_code=201, summary="提交意见反馈（游客可用）")
def submit_feedback(
    body: FeedbackCreate,
    user: Optional[User] = Depends(auth_optional),
    db: Session = Depends(get_db),
):
    """登录态自动带 user_id；游客也可提。App 版本/机型由客户端带上，便于排障。"""
    fb = Feedback(
        user_id=user.id if user else None,
        category=body.category.value,
        content=body.content.strip(),
        contact=body.contact,
        app_version=body.app_version,
        platform=body.platform,
        device_info=body.device_info,
        source_page=body.source_page,
        error_code=body.error_code,
    )
    db.add(fb)
    db.commit()
    db.refresh(fb)
    return FeedbackAccepted(id=fb.id)
