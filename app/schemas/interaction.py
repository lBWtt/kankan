# ============================================================
# 这个文件是干什么的：定义互动类接口的数据形状——想看怎么做（游客可用）、
#   分享记录、分享卡、举报。
# 它对应产品里的什么功能：详情页和线索页上的互动按钮、分享卡底部弹层、举报弹窗。
# 如果它出错了，用户会看到什么现象：点想看怎么做没反应（主信号丢失！）、分享卡生成失败、举报提交不了。
# ============================================================
import uuid
from enum import Enum
from typing import Optional

from pydantic import BaseModel, Field

from app.schemas.common import ShareChannel, ShareStatus
from app.schemas.project import ProjectCounts


class HowToInterestRequest(BaseModel):
    """POST /projects/{id}/how-to-interest：主信号，游客可用（红线：不设登录墙）。
    登录用户服务端取 token 身份；游客必须带 anon_client_id，否则 422 ANON_ID_REQUIRED。
    项目关闭想看怎么做时返回 409 HOW_TO_DISABLED；重复点按幂等成功（不报错）。"""

    anon_client_id: Optional[str] = Field(None, max_length=64, description="游客设备生成的稳定 ID；登录用户可不传")


class HowToInterestResponse(BaseModel):
    ok: bool = True
    how_to_interest_count: int = Field(description="该项目最新累计需求数（前端即时刷新展示）")


class ShareCreate(BaseModel):
    """POST /projects/{id}/shares：记录分享行为，游客可用。clicked=点了分享，completed=确认分享完成。"""

    channel: ShareChannel
    status: ShareStatus
    anon_client_id: Optional[str] = Field(None, max_length=64)


class ShareCardResponse(BaseModel):
    """POST /projects/{id}/share-card：返回分享卡素材（PRD §3.1），客户端渲染成图。
    share_url 回流到 Web 项目分享页（可索引内容页+下载CTA，非下载墙）。"""

    share_url: str
    qr_image_url: Optional[str] = Field(None, description="指向 share_url 的二维码图")
    title: str
    tagline: str
    cover_media_url: Optional[str] = None
    domains: list = []
    category: Optional[str] = None
    counts: ProjectCounts = ProjectCounts()


class ReportReason(str, Enum):
    """举报原因分类（补全决策：按后台 v1.2 审核项推断，将来可调）。"""

    copyright = "copyright"      # 侵权
    ad_spam = "ad_spam"          # 广告/垃圾
    nsfw = "nsfw"                # 低俗不当
    low_quality = "low_quality"  # 低质/标题党
    other = "other"


class ReportCreate(BaseModel):
    """POST /projects/{id}/reports：需登录。"""

    reason: ReportReason
    description: Optional[str] = Field(None, max_length=500)


class ReportCreated(BaseModel):
    ok: bool = True
    report_id: uuid.UUID
