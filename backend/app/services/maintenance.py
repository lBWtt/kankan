# ============================================================
# 这个文件是干什么的：后台定时任务——榜单每小时增量刷新、每日 00:10 全量校准（PRD §7.2），
#   以及清理"上传了但一直没发布"的孤儿媒体（48 小时后连文件一起回收）。
# 它对应产品里的什么功能：本周热门榜的新鲜度；服务器磁盘不被废弃上传塞满。
# 如果它出错了，用户会看到什么现象：榜单一直不更新、老项目赖在榜上；磁盘慢慢被垃圾文件占满。
# ============================================================
import asyncio
import logging
import os
from datetime import datetime, timedelta, timezone
from typing import List

from sqlalchemy import select

from app.core.config import settings
from app.core.db import SessionLocal
from app.models import ProjectMedia
from app.services.rankings import calibrate_hot_scores, refresh_weekly_hot

logger = logging.getLogger("app.maintenance")

STAGED_MEDIA_TTL_HOURS = 48  # 上传后 48 小时仍没挂到任何项目的媒体视为废弃


def purge_staged_media(db, ttl_hours: int = STAGED_MEDIA_TTL_HOURS) -> int:
    """删超时的暂存媒体：数据库行 + 本地文件（只动 /uploads/ 下的，外链 URL 不碰）。返回清理条数。"""
    cutoff = datetime.now(timezone.utc) - timedelta(hours=ttl_hours)
    rows = db.scalars(
        select(ProjectMedia).where(ProjectMedia.project_id.is_(None), ProjectMedia.created_at < cutoff)
    ).all()
    for m in rows:
        if m.url.startswith("/uploads/"):
            path = os.path.join(settings.upload_dir, m.url[len("/uploads/"):])
            try:
                os.remove(path)
            except OSError:
                pass  # 文件已不在（手动删过/换过机器）不影响清行
        db.delete(m)
    db.commit()
    return len(rows)


# ---------- 任务体（独立会话，跑完即还） ----------


def hourly_job() -> None:
    """每小时：本周热门增量刷新（重算上榜分数 + 回写 + 刷缓存）。"""
    with SessionLocal() as db:
        scored = refresh_weekly_hot(db)
    logger.info("榜单小时刷新完成：%d 个项目上榜", len(scored))


def daily_job() -> None:
    """每日 00:10：榜单全量校准（衰减归零的老项目从榜上撤下）+ 孤儿媒体回收。"""
    with SessionLocal() as db:
        updated = calibrate_hot_scores(db)
    with SessionLocal() as db:
        purged = purge_staged_media(db)
    logger.info("每日校准完成：hot_score 更新 %d 条，回收暂存媒体 %d 条", updated, purged)


def ingest_job() -> None:
    """定时整理：把一批 ai_collected 的候选送去 AI 整理（→ ai_processed / pending_review）。
    受当日 AI 调用额度上限约束（超额自动停、下轮再跑），逐条失败跳过不卡整批。"""
    # 惰性导入：避免 maintenance 在 import 期就拉起 AI/openai 依赖链。
    from app.services.ai_processor import process_collected

    with SessionLocal() as db:
        stats = process_collected(db, limit=settings.ingest_batch_limit)
    logger.info(
        "定时整理完成：整理 %d 条（送审 %d，失败 %d，额度截停 %d）",
        stats.get("processed", 0), stats.get("to_review", 0),
        stats.get("failed", 0), stats.get("capped", 0),
    )


# ---------- 调度循环（随 FastAPI 进程启动；MVP 单进程部署，多 worker 时需改成独立任务进程） ----------


def _seconds_until_daily(hour: int = 0, minute: int = 10) -> float:
    """到下一个本地时间 hh:mm 的秒数（运营口径"每日 00:10"按服务器本地时区）。"""
    now = datetime.now()
    target = now.replace(hour=hour, minute=minute, second=0, microsecond=0)
    if target <= now:
        target += timedelta(days=1)
    return (target - now).total_seconds()


async def _hourly_loop() -> None:
    while True:
        await asyncio.sleep(3600)
        try:
            await asyncio.to_thread(hourly_job)
        except Exception:
            logger.exception("榜单小时刷新失败（下个整点重试）")


async def _daily_loop() -> None:
    while True:
        await asyncio.sleep(_seconds_until_daily())
        try:
            await asyncio.to_thread(daily_job)
        except Exception:
            logger.exception("每日校准任务失败（明天 00:10 重试）")


async def _ingest_loop(interval_minutes: int) -> None:
    interval = max(1, interval_minutes) * 60
    while True:
        await asyncio.sleep(interval)
        try:
            await asyncio.to_thread(ingest_job)
        except Exception:
            logger.exception("定时整理任务失败（下一轮重试）")


def start_scheduler() -> List[asyncio.Task]:
    """在 FastAPI lifespan 里调用；返回任务句柄供停服时取消。
    定时整理默认关（ingest_scheduler_enabled=False），开启后按 ingest_interval_minutes 周期跑。"""
    tasks = [asyncio.create_task(_hourly_loop()), asyncio.create_task(_daily_loop())]
    if settings.ingest_scheduler_enabled:
        logger.info("定时整理调度已开启：每 %d 分钟一批", settings.ingest_interval_minutes)
        tasks.append(asyncio.create_task(_ingest_loop(settings.ingest_interval_minutes)))
    return tasks
