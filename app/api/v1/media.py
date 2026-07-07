# ============================================================
# 这个文件是干什么的：媒体上传接口的路由——发布前先传图片/视频，经存储层落本地盘或
#   对象存储，并记一行暂存态媒体（project_id 为空），发布项目时再挂载。
# 它对应产品里的什么功能：发布页的"添加图片/视频"按钮。
# 如果它出错了，用户会看到什么现象：图片传不上去，项目发不出来。
# ============================================================
import os
import tempfile
import uuid

from fastapi import APIRouter, Depends, File, UploadFile
from sqlalchemy.orm import Session

from app.api.deps import ERRORS_AUTHED, auth_required
from app.core.db import get_db
from app.core.errors import AppError
from app.core.ratelimit import rate_limit
from app.models import ProjectMedia, User
from app.schemas.media import MediaUploadResponse
from app.services.storage import save_media_file

router = APIRouter(prefix="/media", tags=["媒体"], responses=ERRORS_AUTHED)

# content-type → (扩展名, 媒体类型, 大小上限字节)；上限实现期可调
_ALLOWED = {
    "image/jpeg": ("jpg", "image", 10 * 1024 * 1024),
    "image/png": ("png", "image", 10 * 1024 * 1024),
    "image/webp": ("webp", "image", 10 * 1024 * 1024),
    "video/mp4": ("mp4", "video", 100 * 1024 * 1024),
}
_CHUNK = 1024 * 1024


def _magic_matches(content_type: str, head: bytes) -> bool:
    """字节头校验：只信文件真实魔数，不信客户端声明的 Content-Type，
    防伪装文件（如把 .html 当 .png 传）经 /uploads 静态托管后被浏览器执行。"""
    if content_type == "image/jpeg":
        return head[:3] == b"\xff\xd8\xff"
    if content_type == "image/png":
        return head[:8] == b"\x89PNG\r\n\x1a\n"
    if content_type == "image/webp":
        return head[:4] == b"RIFF" and head[8:12] == b"WEBP"
    if content_type == "video/mp4":
        return head[4:8] == b"ftyp"  # ISO BMFF：ftyp box 紧跟 4 字节长度
    return False


@router.post("", response_model=MediaUploadResponse, status_code=201, summary="上传图片/视频（需登录，补全端点）")
def upload_media(
    file: UploadFile = File(..., description="图片≤10MB（jpg/png/webp）；视频≤100MB（mp4）"),
    user: User = Depends(auth_required),
    db: Session = Depends(get_db),
):
    """超限/格式不支持 → 422 VALIDATION_FAILED。返回的 id 填进 POST /projects 的 media_ids。
    先写临时文件边写边校验大小，过了再交给存储层（local 落盘 / s3 上传对象存储）。"""
    # H-API-2: 用户级频控——每分钟最多 20 个上传，防磁盘填满 DoS（攻击者循环上传大文件撑爆存储）
    rate_limit(f"media:ul:{user.id}", limit=20, window=60)
    if file.content_type not in _ALLOWED:
        raise AppError(
            422, "VALIDATION_FAILED", "不支持的文件类型",
            {"content_type": file.content_type, "allowed": list(_ALLOWED)},
        )
    ext, media_type, max_bytes = _ALLOWED[file.content_type]
    filename = f"{uuid.uuid4().hex}.{ext}"

    written = 0
    head = b""
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=f".{ext}")
    try:
        while True:
            chunk = file.file.read(_CHUNK)
            if not chunk:
                break
            if not head:  # 首个分块就够看字节头：内容与声明类型不符立刻拒绝，不必落整个盘
                head = chunk[:16]
                if not _magic_matches(file.content_type, head):
                    raise AppError(
                        422, "VALIDATION_FAILED", "文件内容与类型不符（疑似伪装文件）",
                        {"content_type": file.content_type},
                    )
            written += len(chunk)
            if written > max_bytes:
                raise AppError(
                    422, "VALIDATION_FAILED", "文件超过大小上限",
                    {"max_bytes": max_bytes, "media_type": media_type},
                )
            tmp.write(chunk)
        tmp.close()
        if written == 0:
            raise AppError(422, "VALIDATION_FAILED", "文件为空")
        url = save_media_file(tmp.name, filename)
    except Exception:
        tmp.close()
        if os.path.exists(tmp.name):
            os.remove(tmp.name)  # 半截文件不留盘
        raise

    media = ProjectMedia(project_id=None, uploader_user_id=user.id, media_type=media_type, url=url)
    db.add(media)
    db.commit()
    db.refresh(media)
    return MediaUploadResponse(id=media.id, media_type=media.media_type, url=media.url, thumbnail_url=None)
