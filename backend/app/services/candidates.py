# ============================================================
# 这个文件是干什么的：候选审核的核心业务规则——最关键的是 approve：把候选复制成
#   正式项目并发布（字段·API v1.3 §5.3），含发布准入把关和 ai_badge 阈值映射。
# 它对应产品里的什么功能：后台点"通过"按钮后，内容从候选池变成用户能刷到的项目。
# 如果它出错了，用户会看到什么现象：审核通过了但 App 里看不到内容（断供），
#   或不合格内容（纯单图无方法）漏发出去。
# ============================================================
import uuid
from datetime import datetime, timezone
from typing import List, Optional
from urllib.parse import urlparse

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.errors import AppError
from app.models import CandidateContent, Post, PostMedia, Project, ProjectMedia, User
from app.services.audit import log_admin_action
from app.services.media_transfer import transfer_candidate_media
from app.services.personas import pick_persona_for
from app.services.publishing import attach_tags

# 这些状态允许 discard / park / 编辑；approved 和 discarded 是终态
ACTIONABLE_STATUSES = {"ai_collected", "ai_processed", "pending_review", "edited", "parked"}
# approve 比其它动作更严：ai_collected（刚抓回来、未经 AI 整理或人工编辑）不许直接发布——
# 必须先经 ai_processed/pending_review 或人工 edited，杜绝跳过整理流程把生料推上线。
APPROVABLE_STATUSES = {"ai_processed", "pending_review", "edited", "parked"}

_URL_EXPERIENCE_TYPES = {"web", "video", "gallery", "download", "model_page", "game"}
_EXPERIENCE_TYPES = _URL_EXPERIENCE_TYPES | {"workflow_file", "prompt_content"}
_BAD_PROOF_MARKERS = (
    "opengraph.githubassets.com", "github-social", "github-social-preview",
    "shields.io", "badge", "/logo", "logo.", "/icon", "icon.",
    "avatars.githubusercontent", "s.wordpress.com/mshots",
)


def badge_for_score(score: Optional[int]) -> str:
    """内容宪法 v1.1：≥82 强候选；70-81 可发布；其余不展示 badge。"""
    if score is None:
        return "none"
    if score >= 82:
        return "high_potential"
    if score >= 70:
        return "worth_a_look"
    return "none"


def _as_list(value) -> list:
    """tags_json / media_json 兼容两种存法：直接列表，或 {"items"/"tags": [...]} 包一层。"""
    if isinstance(value, list):
        return value
    if isinstance(value, dict):
        for key in ("items", "tags"):
            if isinstance(value.get(key), list):
                return value[key]
    return []


def ensure_actionable(candidate: CandidateContent, action: str) -> None:
    if candidate.status not in ACTIONABLE_STATUSES:
        raise AppError(
            409,
            "CANDIDATE_INVALID_STATE",
            f"候选当前状态为 {candidate.status}，不允许执行 {action}",
            {"status": candidate.status},
        )


def ensure_approvable(candidate: CandidateContent) -> None:
    if candidate.status not in APPROVABLE_STATUSES:
        raise AppError(
            409,
            "CANDIDATE_INVALID_STATE",
            f"候选当前状态为 {candidate.status}，不允许 approve："
            "ai_collected 必须先经 AI 整理或人工编辑后才能发布",
            {"status": candidate.status},
        )


def _media_items(candidate: CandidateContent) -> list:
    return _as_list(candidate.media_json)


def is_valid_proof_media(item: object) -> bool:
    """保守识别成果证据；明确的社交卡/logo/icon/官网截图不能混成 proof。"""
    if not isinstance(item, dict):
        return False
    url = str(item.get("url") or "").strip()
    kind = str(item.get("media_type") or item.get("type") or "image").lower()
    if not url or kind not in {"image", "video"}:
        return False
    low = url.lower()
    return not any(marker in low for marker in _BAD_PROOF_MARKERS)


def select_proof_media(candidate: CandidateContent, preferred_index: Optional[int] = None) -> Optional[dict]:
    """按 AI 选择的索引取 proof；索引无效时不擅自把第一张普通图当成果证据。"""
    items = _media_items(candidate)
    if preferred_index is None or preferred_index < 0 or preferred_index >= len(items):
        return None
    item = items[preferred_index]
    return dict(item) if is_valid_proof_media(item) else None


def proof_media_for_transfer(candidate: CandidateContent) -> list:
    """selected proof 排第一，其余合格效果媒体随后；发布只转存这组，不带丑卡。"""
    selected = candidate.selected_proof_media if is_valid_proof_media(candidate.selected_proof_media) else None
    out = [dict(selected)] if selected else []
    selected_url = str(selected.get("url")) if selected else None
    for item in _media_items(candidate):
        if is_valid_proof_media(item) and str(item.get("url")) != selected_url:
            out.append(dict(item))
    return out


def _experience_problem(candidate: CandidateContent) -> Optional[str]:
    kind = (candidate.experience_type or "").strip()
    url = (candidate.experience_url or "").strip()
    content = (candidate.experience_content or "").strip()
    if not kind:
        return "experience_type 缺失"
    if kind not in _EXPERIENCE_TYPES:
        return f"未知 experience_type：{kind}"
    if kind in _URL_EXPERIENCE_TYPES:
        if not url:
            return f"{kind} 类型必须有 experience_url"
        if not url.startswith(("http://", "https://")):
            return "experience_url 必须是 http/https 地址"
        parsed = urlparse(url)
        host = (parsed.hostname or "").lower()
        # 宪法 9.2：GitHub repo 是代码出处，不是作品体验。GitHub Pages（github.io）不受影响；
        # download 类型允许直达 release 资产，但普通仓库/README/releases 列表都要补官网或 hosted demo。
        if host in {"github.com", "www.github.com"} and not (
            kind == "download" and "/releases/download/" in parsed.path.lower()
        ):
            return "GitHub 仓库页不能作为体验入口；请补 hosted demo、官网或直接下载地址"
    elif kind == "prompt_content" and not content:
        return "prompt_content 类型必须有 experience_content"
    elif kind == "workflow_file" and not (url or content):
        return "workflow_file 必须有 URL 或可复用内容"
    return None


def _rolling_mix_problems(db: Session, candidate: CandidateContent) -> List[str]:
    recent = db.execute(
        select(Project.creator_type, Project.access_friction)
        .where(Project.status == "published", Project.deleted_at.is_(None))
        .order_by(Project.published_at.desc(), Project.id.desc())
        .limit(100)
    ).all()
    problems: List[str] = []
    if candidate.creator_type == "company" and sum(1 for creator, _ in recent if creator == "company") >= 5:
        problems.append("最近 100 条 company 已达 5 条上限")
    if candidate.access_friction == "technical" and sum(1 for _, friction in recent if friction == "technical") >= 15:
        problems.append("最近 100 条 technical 已达 15 条上限")
    return problems


def check_publish_gate(
    candidate: CandidateContent,
    *,
    db: Optional[Session] = None,
    transferred_media: Optional[list] = None,
) -> None:
    """内容宪法 v1.1 发布准入。传 transferred_media 表示最终发布 gate。"""
    problems: List[str] = []
    if candidate.is_work is not True:
        problems.append("不是完整作品（作品/原料闸未通过）")
    if not candidate.title or not (12 <= len(candidate.title.strip()) <= 28):
        problems.append("hook_title 必须为 12～28 个可见字符")
    if not candidate.tagline or len(candidate.tagline) < 5:
        problems.append("hook_sentence 缺失或过短（≥5 字）")
    if not candidate.summary or len(candidate.summary) < 20:
        problems.append("summary 缺失或过短（≥20 字）")
    if not candidate.category:
        problems.append("category 缺失")
    if not candidate.domains:
        problems.append("domains 至少 1 个")
    if not candidate.work_form or not candidate.creator_type or not candidate.access_friction:
        problems.append("work_form / creator_type / access_friction 不完整")
    score_fields = ("hook_clarity", "visual_impact", "surprise", "tryability", "shareability", "attraction_score", "value_score")
    if any(getattr(candidate, field, None) is None for field in score_fields):
        problems.append("吸引力五维、attraction_score、value_score 必须完整")
    elif candidate.attraction_score < 70:
        problems.append("attraction_score < 70：不得发布")
    if not is_valid_proof_media(candidate.selected_proof_media):
        problems.append("缺少人工/AI 选定的成果证据媒体 selected_proof_media")
    if transferred_media is not None and not any(
        isinstance(item, dict) and item.get("url") and item.get("media_type") in {"image", "video"}
        for item in transferred_media
    ):
        problems.append("成果媒体转存全部失败，不得发布")
    exp_problem = _experience_problem(candidate)
    if exp_problem:
        problems.append(exp_problem)
    if db is not None:
        problems.extend(_rolling_mix_problems(db, candidate))
    if problems:
        raise AppError(409, "PUBLISH_GATE_FAILED", "发布准入不满足，不能通过", {"problems": problems})


def check_post_gate(candidate: CandidateContent) -> None:
    """动态（content_kind=post）发布准入：正文（存 summary）够长 + 至少 1 个标签。
    动态无封面/分类/领域要求（可纯文字），故门槛比项目松。"""
    problems: List[str] = []
    if not candidate.summary or len(candidate.summary.strip()) < 20:
        problems.append("动态正文缺失或过短（≥20 字）")
    if not _as_list(candidate.tags_json):
        problems.append("话题标签至少 1 个")
    if problems:
        raise AppError(409, "PUBLISH_GATE_FAILED", "动态发布准入不满足，不能通过", {"problems": problems})


def _lock_approvable(db: Session, candidate: CandidateContent) -> CandidateContent:
    """approve 入口共用：SELECT ... FOR UPDATE 重载候选行并刷新 identity map（并发安全 C-SVC-1），
    校验状态可 approve。返回加锁后的候选行。"""
    locked = db.execute(
        select(CandidateContent)
        .where(CandidateContent.id == candidate.id)
        .with_for_update()
        .execution_options(populate_existing=True)
    ).scalar_one_or_none()
    if locked is None:
        raise AppError(404, "NOT_FOUND", "候选不存在")
    ensure_approvable(locked)
    return locked


def approve_candidate_as_post(db: Session, candidate: CandidateContent, admin: User) -> Post:
    """§动态：候选（content_kind=post）→ 马甲发的正式动态。正文取 summary、标签取 tags_json，
    图片转存后落 post_media（动态仅图片，视频跳过）。无马甲则拒绝（动态必须有作者）。"""
    candidate = _lock_approvable(db, candidate)
    check_post_gate(candidate)

    persona = pick_persona_for(db, category=candidate.category, domains=candidate.domains)
    if persona is None:
        raise AppError(409, "NO_PERSONA", "没有可用马甲号，无法发布动态（先跑 seed_personas.py）")

    # 图片转存（动态仅图片；外链防盗链，下载到本地/OSS 再落表）
    transferred = [t for t in transfer_candidate_media(_as_list(candidate.media_json), candidate.source_platform)
                   if t.get("media_type") == "image"]

    now = datetime.now(timezone.utc)
    post = Post(
        author_user_id=persona.id,
        content=(candidate.summary or "").strip(),
        tags=_as_list(candidate.tags_json)[:5],
    )
    db.add(post)
    db.flush()  # 拿 post.id
    for i, item in enumerate(transferred):
        db.add(PostMedia(post_id=post.id, media_type="image", url=item["url"], sort_order=i))

    candidate.status = "approved"
    candidate.reviewed_by_user_id = admin.id
    candidate.reviewed_at = now
    log_admin_action(db, admin.id, "approve_candidate_post", "candidate", candidate.id,
                     {"post_id": str(post.id)})
    return post


def approve_candidate(db: Session, candidate: CandidateContent, admin: User) -> Project:
    """§5.3 复制 + 关联：候选 → 正式项目（published，hot_score=0），媒体/标签一并落表，回写 project_id。

    并发安全（C-SVC-1）：approve 入口用 SELECT ... FOR UPDATE 重新加载候选行并刷新
    identity map 的属性。两个并发 approve 同一候选时，B 的 FOR UPDATE 会阻塞到 A
    提交后再读到 status=approved，由 ensure_approvable 抛 409 CANDIDATE_INVALID_STATE，
    杜绝“两个 published 项目、candidate.project_id 只指向后提交的、先创建的变孤儿”。
    锁在 service 内部获取，API 层 admin.py approve 端点无需改动（其 db.commit() 释放锁）。
    """
    # 即使 admin 端点已 db.get 过，这里仍要重新 FOR UPDATE：既加行锁，又用 populate_existing
    # 把 identity map 里的旧属性（如 status=pending_review）刷新成数据库提交后的最新值。
    candidate = _lock_approvable(db, candidate)
    # 先做无外部副作用的字段预检；随后转存 proof，成功后再跑最终 gate。
    check_publish_gate(candidate)

    transferred = transfer_candidate_media(proof_media_for_transfer(candidate), candidate.source_platform)
    check_publish_gate(candidate, db=db, transferred_media=transferred)
    cover_url = next((t["url"] for t in transferred if t.get("media_type") == "image"), None)
    if cover_url is None and transferred:
        cover_url = transferred[0].get("thumbnail_url")

    # 马甲发布（决策：让外部内容读起来像真实用户自己发的帖）：随机派一个马甲当作者。
    # 「完全不留出处」：原作者名/链接不落到项目上（不展示）；source_url 仍留作去重/内部备查，
    # 前端只对 GitHub 源渲染出处卡，其余不显示，故不会露出小红书/抖音来源。
    persona = pick_persona_for(db, category=candidate.category, domains=candidate.domains)

    now = datetime.now(timezone.utc)
    project = Project(
        author_user_id=persona.id if persona else None,  # 马甲作者（无马甲则回退无站内作者）
        title=candidate.title,
        tagline=candidate.tagline,
        summary=candidate.summary,
        description=candidate.description,
        category=candidate.category,
        language=candidate.language,
        source_type=candidate.source_type,
        is_original=False,
        source_url=candidate.source_url,  # 内部备查/去重用，不展示
        try_url=candidate.try_url,        # 体验入口（DeepSeek 提取，小红书/抖音成果尤其重要）
        work_form=candidate.work_form,
        creator_type=candidate.creator_type,
        access_friction=candidate.access_friction,
        experience_type=candidate.experience_type,
        experience_url=candidate.experience_url,
        experience_content=candidate.experience_content,
        hook_clarity=candidate.hook_clarity,
        visual_impact=candidate.visual_impact,
        surprise=candidate.surprise,
        tryability=candidate.tryability,
        shareability=candidate.shareability,
        attraction_score=candidate.attraction_score,
        value_score=candidate.value_score,
        is_strong_visual=candidate.is_strong_visual,
        is_direct_tryable=candidate.is_direct_tryable,
        selected_proof_media=transferred[0] if transferred else None,
        title_candidates=candidate.title_candidates,
        policy_version=candidate.policy_version,
        score_version=candidate.score_version,
        ai_analysis_json=candidate.ai_analysis_json,
        human_override_json=candidate.human_override_json,
        override_reason=candidate.override_reason,
        source_platform=candidate.source_platform,
        original_author_name=None,  # 不留出处
        original_author_url=None,
        cover_media_url=cover_url,
        tools=candidate.tools or [],
        domains=candidate.domains or [],
        ai_badge=badge_for_score(candidate.ai_curation_score),
        ai_implementation_hint=candidate.ai_implementation_hint,
        target_users=candidate.target_users,
        use_cases=candidate.use_cases,
        status="published",
        hot_score=0,
        published_at=now,
    )
    db.add(project)
    db.flush()  # 拿到 project.id

    # 媒体：转存后的 URL（已下载到本地/OSS，非外链）→ project_media 落表
    for i, item in enumerate(transferred):
        db.add(
            ProjectMedia(
                project_id=project.id,
                media_type=item.get("media_type", "image"),
                url=item["url"],
                thumbnail_url=item.get("thumbnail_url"),
                sort_order=i,
            )
        )

    # 标签：tags_json 拆解 → 字典表去重 + 关系表（与用户发布共用 attach_tags）
    attach_tags(db, project.id, _as_list(candidate.tags_json))

    candidate.status = "approved"
    candidate.project_id = project.id
    candidate.reviewed_by_user_id = admin.id
    candidate.reviewed_at = now

    log_admin_action(db, admin.id, "approve_candidate", "candidate", candidate.id,
                     {"project_id": str(project.id)})
    return project


def transition_candidate(
    db: Session, candidate: CandidateContent, admin: User, new_status: str, reason: Optional[str] = None
) -> None:
    """discard / park 共用的简单状态流转 + 留痕。"""
    ensure_actionable(candidate, new_status)
    candidate.status = new_status
    candidate.reviewed_by_user_id = admin.id
    candidate.reviewed_at = datetime.now(timezone.utc)
    log_admin_action(db, admin.id, f"{new_status}_candidate", "candidate", candidate.id,
                     {"reason": reason} if reason else None)
