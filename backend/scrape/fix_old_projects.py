# ============================================================
# 一次性维护脚本（跑完可删）：
#   1) 重写「旧写法」的已发布项目——用新提示词(ai_processor._SYSTEM_PROMPT)重跑
#      标题/亮点/简介/描述，去掉 作者/来源平台/教程/复刻/第一人称 这些旧措辞。
#      只改文案字段(title/tagline/summary/description/tools/target_users/use_cases/try_url)，
#      不动 category/domains/封面/来源/评分/热度——避免副作用。
#   2) 清理卡在 ai_processed 的项目候选（都是被 is_maker_showcase 门槛正确拦下的
#      广告/教程/水，标了 low_quality）——置为 discarded，清空积压。
#
# 用法（在 backend/ 下；DeepSeek key 只经环境变量传，绝不写进文件/提交）：
#   $env:AI_PROVIDER="deepseek"; $env:DEEPSEEK_API_KEY="sk-xxx"; $env:PYTHONIOENCODING="utf-8"
#   python scrape/fix_old_projects.py            # 真跑
#   python scrape/fix_old_projects.py --dry-run  # 只看会改哪些，不写库
# ============================================================
from __future__ import annotations

import argparse
import re
import sys

from sqlalchemy import select

from app.core.db import SessionLocal
from app.models import CandidateContent, Project
from app.services.ai_processor import get_analyzer, _paragraphize

# 判定「旧写法」的禁词：指向来源/作者、第一人称冒充。
# 关键：「作者」要排除 创作者(creator)/原作者(字段名) 这类合法词——用负向后行断言。
# 不含「教程/复刻」——那是内容类型（源本身就是教程），不属于写法问题，重写也不该硬改。
FORBID = re.compile(
    r"(?<![创原])作者|博主|网友|一位用户|一位开发者|有人做了|up主|据说|转发|亲测"
)


def _is_dirty(*texts) -> bool:
    return FORBID.search(" ".join(t for t in texts if t)) is not None


def _payload_from_project(db, p: Project) -> dict:
    """给重写用的 payload：优先用来源候选的原始正文；没有就退回项目自身现有文案。"""
    cand = None
    if p.source_url:
        cand = db.scalars(
            select(CandidateContent).where(CandidateContent.source_url == p.source_url)
        ).first()
    raw = (cand.raw_json or {}) if cand else {}
    raw_text = (raw.get("text") or "").strip()
    if not raw_text:
        # 没有原始正文：用项目现有 简介+描述 当原料，让模型按新规则清洗重写。
        raw_text = "\n".join(x for x in [p.summary, p.description] if x).strip()
    return {
        "原文标题": (raw.get("title") or p.title or "")[:200],
        "原始正文": raw_text[:6000],
        "来源平台": p.source_platform or "未知",
        "来源链接": p.source_url or "",
        "原作者": p.original_author_name or "未识别",
        "媒体数量": 1 if p.cover_media_url else 0,
        "语言": p.language,
    }


def _clean_try_url(try_url, source_url) -> str | None:
    """别把帖子出处（抖音/小红书视频页）当体验入口（与 ai_processor.apply_analysis 同规则）。"""
    tu = (try_url or "").strip() or None
    if tu and (
        tu == (source_url or "")
        or "douyin.com/video" in tu
        or "xiaohongshu.com" in tu
        or "/note/" in tu
        or "v.douyin.com" in tu
    ):
        return None
    return tu


def _analyze_clean(analyze, payload, tries: int = 3):
    """重跑分析，直到产出不含禁词（DeepSeek 偶尔会把 作者/亲测 又写回去）。
    tries 次都不干净就返回最后一次（仍比旧版好），交由调用方决定。"""
    last = None
    for _ in range(max(1, tries)):
        a = analyze(payload)
        last = a
        if not _is_dirty(a.title, a.tagline, a.summary, a.description):
            return a, True
    return last, False


def rewrite_old_projects(db, analyze, dry_run: bool) -> int:
    # 全量拉在线项目，Python 侧按 title+summary+description 判禁词（排除 创作者/原作者）。
    all_live = db.scalars(
        select(Project).where(Project.deleted_at.is_(None))
    ).all()
    projs = [p for p in all_live if _is_dirty(p.title, p.summary, p.description)]
    print(f"\n== 重写旧写法项目：命中 {len(projs)} 个 ==")
    done, dirty_left = 0, 0
    for p in projs:
        try:
            a, clean = _analyze_clean(analyze, _payload_from_project(db, p))
        except Exception as e:  # noqa: BLE001
            print(f"  [跳过] {p.title[:24]} — 分析失败：{e}")
            continue
        flag = "" if clean else "  ⚠仍含禁词(已尽力)"
        print(f"\n  旧：{p.title}{flag}")
        print(f"      {(p.summary or '')[:70]}")
        print(f"  新：{a.title}")
        print(f"      {(a.summary or '')[:70]}")
        if not clean:
            dirty_left += 1
        if dry_run:
            continue
        p.title = a.title[:80]
        p.tagline = a.tagline[:140]
        p.summary = a.summary[:500]
        p.description = _paragraphize(a.description)
        p.tools = a.tools[:10]
        p.target_users = a.target_users[:5] or None
        p.use_cases = a.use_cases[:5] or None
        p.try_url = _clean_try_url(a.try_url, p.source_url)
        db.commit()
        done += 1
    tail = "（--dry-run 未写库）" if dry_run else ""
    print(f"\n  重写完成 {done}/{len(projs)}{tail}；仍含禁词 {dirty_left} 个")
    return done


def discard_stuck_candidates(db, dry_run: bool) -> int:
    cands = db.scalars(
        select(CandidateContent).where(
            CandidateContent.status == "ai_processed",
            CandidateContent.content_kind == "project",
        )
    ).all()
    print(f"\n== 清理卡住的项目候选：{len(cands)} 条（都被门槛拦下的广告/教程/水）==")
    if dry_run:
        for c in cands[:10]:
            print(f"  [dry] discard: {c.source_platform} · {(c.title or '')[:34]}")
        return 0
    for c in cands:
        c.status = "discarded"
    db.commit()
    print(f"  已置为 discarded：{len(cands)} 条")
    return len(cands)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--skip-rewrite", action="store_true")
    ap.add_argument("--skip-discard", action="store_true")
    args = ap.parse_args()

    analyze = get_analyzer()
    with SessionLocal() as db:
        if not args.skip_rewrite:
            rewrite_old_projects(db, analyze, args.dry_run)
        if not args.skip_discard:
            discard_stuck_candidates(db, args.dry_run)
    return 0


if __name__ == "__main__":
    sys.exit(main())
