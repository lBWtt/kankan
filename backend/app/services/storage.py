# ============================================================
# 这个文件是干什么的：媒体文件存储的统一出入口——local 后端落本地盘（经 /uploads 静态托管），
#   s3 后端传 S3 兼容对象存储（阿里云 OSS 的 S3 兼容端点 / AWS S3 / MinIO 均可）。
# 它对应产品里的什么功能：发布页上传的图片/视频最终存在哪、用户刷到的图从哪个域名加载。
# 如果它出错了，用户会看到什么现象：图片传不上去，或传上去了但全 App 的图都裂开。
# ============================================================
import os
import shutil

from app.core.config import settings

_S3_CONTENT_TYPES = {
    "jpg": "image/jpeg", "png": "image/png", "webp": "image/webp", "mp4": "video/mp4",
}


def save_media_file(temp_path: str, filename: str) -> str:
    """把已写好的临时文件收进存储，返回公开访问 URL。temp_path 由调用方负责保证存在；
    本函数成功后临时文件即被移走/删除。"""
    if settings.storage_backend == "s3":
        return _save_s3(temp_path, filename)
    return _save_local(temp_path, filename)


def _save_local(temp_path: str, filename: str) -> str:
    os.makedirs(settings.upload_dir, exist_ok=True)
    shutil.move(temp_path, os.path.join(settings.upload_dir, filename))
    return f"/uploads/{filename}"


def _save_s3(temp_path: str, filename: str) -> str:
    """boto3 按需导入：local 后端跑开发环境不需要装它也能起服务。"""
    try:
        import boto3
    except ImportError as exc:  # pragma: no cover
        raise RuntimeError("storage_backend=s3 需要安装 boto3（pip install boto3）") from exc

    client = boto3.client(
        "s3",
        endpoint_url=settings.s3_endpoint_url,
        aws_access_key_id=settings.s3_access_key_id,
        aws_secret_access_key=settings.s3_secret_access_key,
        region_name=settings.s3_region or None,
    )
    ext = filename.rsplit(".", 1)[-1]
    key = f"media/{filename}"
    client.upload_file(
        temp_path, settings.s3_bucket, key,
        ExtraArgs={"ContentType": _S3_CONTENT_TYPES.get(ext, "application/octet-stream")},
    )
    os.remove(temp_path)
    return f"{settings.s3_public_base_url.rstrip('/')}/{key}"
