# ============================================================
# 这个文件是干什么的：定义媒体上传接口的数据形状——发布项目前先把图片/视频传上来，
#   拿到 media_id 再填进发布请求。
# 它对应产品里的什么功能：发布页的"添加图片/视频"。
# 如果它出错了，用户会看到什么现象：发布时图片传不上去，项目发不出来。
# ============================================================
import uuid
from enum import Enum
from typing import Optional

from pydantic import BaseModel


class MediaType(str, Enum):
    image = "image"
    video = "video"


class MediaUploadResponse(BaseModel):
    """POST /media（multipart 文件上传）的返回。
    补全决策：POST /projects 要求 media_ids（§8），但字段文档没给上传端点，此为必要补充。"""

    id: uuid.UUID
    media_type: MediaType
    url: str
    thumbnail_url: Optional[str] = None
