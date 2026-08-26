"""从社交视频里自动抽少量候选成果帧，供审核员挑选/删除。

只负责提供更多视觉证据，不据此提高 visual_impact；分数突破仍需人工看图确认。
失败时返回空列表，不能阻断 DeepSeek 整理主流程。
"""
import logging
import os
import shutil
import tempfile
import uuid
from typing import Optional

try:
    import cv2
except ImportError:  # 部署依赖异常时不能拖垮整个 API；抽帧降级为空。
    cv2 = None

from app.services.media_transfer import _headers_for, _make_client
from app.services.storage import save_media_file
from app.core.config import settings

logger = logging.getLogger("app.video_frames")

_SUPPORTED_PLATFORMS = {"douyin", "xiaohongshu"}
_SAMPLE_RATIOS = (0.20, 0.50, 0.80)
_MAX_VIDEO_BYTES = 80 * 1024 * 1024


def _download_video(url: str, platform: Optional[str]) -> Optional[str]:
    path = None
    try:
        # 媒体转存后 URL 是 /uploads/...；它在后端容器里已经是本地文件，
        # 不应再交给 httpx 当公网地址下载，否则每条都会报 missing protocol 并超时。
        if url.startswith("/uploads/"):
            source = os.path.join(settings.upload_dir, url.removeprefix("/uploads/"))
            if not os.path.isfile(source):
                raise FileNotFoundError(f"站内视频不存在: {source}")
            fd, path = tempfile.mkstemp(suffix=os.path.splitext(source)[1] or ".mp4")
            os.close(fd)
            shutil.copyfile(source, path)
            return path
        fd, path = tempfile.mkstemp(suffix=".mp4")
        total = 0
        with os.fdopen(fd, "wb") as out, _make_client() as client:
            with client.stream("GET", url, headers=_headers_for(platform)) as response:
                response.raise_for_status()
                for chunk in response.iter_bytes(65536):
                    total += len(chunk)
                    if total > _MAX_VIDEO_BYTES:
                        raise ValueError("视频超过关键帧提取上限")
                    out.write(chunk)
        if total < 4096:
            raise ValueError("视频内容过小")
        return path
    except Exception as exc:
        logger.warning("关键帧视频下载失败 platform=%s url=%s err=%s", platform, url[:80], exc)
        if path and os.path.exists(path):
            os.remove(path)
        return None


def _fingerprint(frame) -> int:
    """64 位感知指纹，避免三个采样点截到几乎相同的静止画面。"""
    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    small = cv2.resize(gray, (9, 8), interpolation=cv2.INTER_AREA)
    bits = small[:, 1:] > small[:, :-1]
    value = 0
    for bit in bits.flat:
        value = (value << 1) | int(bit)
    return value


def _usable(frame) -> bool:
    if frame is None or frame.size == 0:
        return False
    height, width = frame.shape[:2]
    if width < 320 or height < 240:
        return False
    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    mean = float(gray.mean())
    sharpness = float(cv2.Laplacian(gray, cv2.CV_64F).var())
    return 12 <= mean <= 243 and sharpness >= 18


def extract_candidate_frames(candidate, max_frames: int = 3) -> list[dict]:
    """从候选第一个视频抽帧并追加为我们的稳定 /uploads URL。"""
    platform = (candidate.source_platform or "").lower()
    if cv2 is None or platform not in _SUPPORTED_PLATFORMS:
        return []
    items = list((candidate.media_json or {}).get("items") or [])
    video = next((item for item in items if isinstance(item, dict)
                  and item.get("media_type") == "video" and item.get("url")), None)
    if not video:
        return []
    # 已生成过就不重复下载/抽帧，保证 process 重试幂等。
    if any(isinstance(item, dict) and item.get("generated_from") == "video_frame" for item in items):
        return []

    video_path = _download_video(str(video["url"]), platform)
    if not video_path:
        return []
    capture = cv2.VideoCapture(video_path)
    generated: list[dict] = []
    frame_temps: list[str] = []
    try:
        frame_count = int(capture.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
        if frame_count <= 3:
            return []
        fingerprints: list[int] = []
        for ratio in _SAMPLE_RATIOS:
            capture.set(cv2.CAP_PROP_POS_FRAMES, max(0, int((frame_count - 1) * ratio)))
            ok, frame = capture.read()
            if not ok or not _usable(frame):
                continue
            fp = _fingerprint(frame)
            if any(bin(int(fp ^ old)).count("1") < 9 for old in fingerprints):
                continue
            fingerprints.append(fp)
            fd, temp_path = tempfile.mkstemp(suffix=".jpg")
            os.close(fd)
            frame_temps.append(temp_path)
            ok, encoded = cv2.imencode(".jpg", frame, [cv2.IMWRITE_JPEG_QUALITY, 88])
            if not ok:
                continue
            # cv2.imwrite 在含中文用户名的 Windows 路径上会失败；由 Python 写编码结果可兼容。
            with open(temp_path, "wb") as output:
                output.write(encoded.tobytes())
            public_url = save_media_file(temp_path, f"frame_{uuid.uuid4().hex}.jpg")
            frame_temps.remove(temp_path)  # save_media_file 已移动/删除
            generated.append({
                "url": public_url,
                "media_type": "image",
                "generated_from": "video_frame",
                "frame_ratio": ratio,
            })
            if len(generated) >= max_frames:
                break
        return generated
    except Exception as exc:
        logger.warning("候选关键帧提取失败 candidate_id=%s err=%s", candidate.id, exc)
        return []
    finally:
        capture.release()
        if os.path.exists(video_path):
            os.remove(video_path)
        for path in frame_temps:
            if os.path.exists(path):
                os.remove(path)


def backfill_candidate_frames(db, *, limit: int = 20, source_platform: Optional[str] = None) -> dict:
    """给已整理但尚未发布的候选补关键帧；逐条提交，单条失败不影响整批。"""
    from sqlalchemy import select
    from app.models import CandidateContent

    stmt = select(CandidateContent).where(
        CandidateContent.status.in_(("ai_processed", "pending_review", "edited"))
    )
    if source_platform:
        stmt = stmt.where(CandidateContent.source_platform == source_platform)
    rows = db.execute(stmt.order_by(CandidateContent.updated_at.desc()).limit(limit)).scalars().all()
    stats = {"scanned": len(rows), "enriched": 0, "frames": 0, "failed": 0}
    for candidate in rows:
        try:
            generated = extract_candidate_frames(candidate)
            if generated:
                items = list((candidate.media_json or {}).get("items") or [])
                items.extend(generated)
                candidate.media_json = {"items": items}
                stats["enriched"] += 1
                stats["frames"] += len(generated)
            db.commit()
        except Exception:
            db.rollback()
            stats["failed"] += 1
            logger.exception("候选关键帧回填失败 candidate_id=%s", candidate.id)
    return stats
