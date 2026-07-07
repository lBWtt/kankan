# ============================================================
# 这个文件是干什么的：用户发布链路的业务逻辑车间——发布准入把关、暂存媒体挂载、
#   标签落表、"我做了类似的"建链与通知（§5.2）、编辑与软删除。
# 它对应产品里的什么功能：发布 Tab（原创上传 / 发现分享）、编辑/删除自己的项目、
#   "我做了类似的"入口。
# 如果它出错了，用户会看到什么现象：发不了项目、发出去的项目缺图缺标签，
#   或不合格内容（纯单图无方法）漏发出去。
# ============================================================
import uuid
from datetime import datetime, timezone
from typing import List, Optional
from urllib.parse import urlparse

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.errors import AppError
from app.models import (
    Notification,
    Project,
    ProjectAction,
    ProjectMedia,
    ProjectTag,
    ProjectTagRelation,
    SimilarProjectLink,
    User,
)
from app.schemas.project import ProjectCreate, ProjectUpdate


def check_user_publish_gate(tools: List[str], description: Optional[str]) -> None:
    """发布准入（PRD §2.3 红线）：tools≥1 或简介含可复现说明；纯单图无方法不发布。
    可复现说明的启发式与候选审核一致：description≥20 字（summary 被 schema 强制 ≥20 字，
    不能用作准入依据，否则准入形同虚设——补全决策）。"""
    if not tools and not (description and len(description.strip()) >= 20):
        raise AppError(
            409, "PUBLISH_GATE_FAILED", "发布准入不满足：需要至少 1 个工具，或在详情里写明可复现方法（≥20 字）",
            {"problems": ["准入不满足：tools≥1 或 description 含可复现方法说明（≥20 字）"]},
        )


_VERTICAL_DEFAULTS = {
    "Vibe Coding": ("creator_tools", ["dev"]),
    "知识管理": ("learning_growth", ["office"]),
    "视频创作": ("video_music", ["video"]),
    "内容运营": ("work_efficiency", ["marketing"]),
    "音乐创作": ("video_music", ["other"]),
    "设计": ("image_design", ["design"]),
    "效率工具": ("work_efficiency", ["office"]),
    "其他": ("future_cases", ["other"]),
}


def _clean_text(value: Optional[str]) -> Optional[str]:
    if value is None:
        return None
    value = value.strip()
    return value or None


def _clip(value: str, limit: int) -> str:
    return value[:limit]


def _source_type_from_body(body: ProjectCreate) -> str:
    if body.source_kind in ("curated", "user_discovery"):
        return "user_discovery"
    if body.is_original:
        return "user_original"
    return "user_discovery"


def _is_original_from_body(body: ProjectCreate) -> bool:
    if body.source_kind in ("curated", "user_discovery"):
        return False
    if body.source_kind in ("original", "user_original"):
        return True
    return body.is_original


def _derive_category_domains(body: ProjectCreate) -> tuple[str, list[str]]:
    default_category, default_domains = _VERTICAL_DEFAULTS.get(body.vertical or "", ("creator_tools", ["other"]))
    category = body.category.value if body.category else default_category
    domains = [d.value if hasattr(d, "value") else d for d in body.domains] or default_domains
    return category, domains


def _derive_public_text(body: ProjectCreate) -> tuple[str, str, str, Optional[str]]:
    intro = _clean_text(body.intro) or _clean_text(body.description) or _clean_text(body.summary) or ""
    title = _clean_text(body.title)
    if title is None:
        title = intro.splitlines()[0][:80] if intro else "AI 创意项目"
    title = _clip(title, 80)
    if len(title) < 2:
        title = f"{title}项目"

    tagline = _clean_text(body.tagline) or _clip(intro or title, 140)
    if len(tagline) < 5:
        tagline = f"{tagline}，值得一看"
    tagline = _clip(tagline, 140)

    summary = _clean_text(body.summary) or _clip(intro or tagline, 500)
    if len(summary) < 20:
        summary = _clip(f"{summary} 这个项目提供了可复现的做法和使用线索。", 500)

    description = _clean_text(body.description) or (intro if intro and intro != summary else None)
    return title, tagline, summary, description


def _validate_action_url(raw: Optional[str]) -> Optional[str]:
    raw = _clean_text(raw)
    if raw is None:
        return None
    parsed = urlparse(raw)
    if parsed.scheme not in ("http", "https") or not parsed.netloc:
        raise AppError(422, "VALIDATION_FAILED", "action.url 只允许 http/https 链接")
    return raw


def _check_project_v2_gate(body: ProjectCreate) -> None:
    """新版发布准入：有 action 视为有可执行方法；否则沿用 tools 或详情方法说明。"""
    method_text = body.description or body.intro
    if body.actions:
        return
    check_user_publish_gate(body.tools, method_text)


def _create_project_actions(db: Session, project: Project, body: ProjectCreate) -> None:
    for idx, action in enumerate(body.actions):
        if action.file_media_id is not None:
            media = db.get(ProjectMedia, action.file_media_id)
            if media is None or media.project_id != project.id:
                raise AppError(422, "VALIDATION_FAILED", "action.file_media_id 必须指向当前项目已挂载的媒体")
        db.add(
            ProjectAction(
                project_id=project.id,
                action_type=action.action_type.value,
                action_sub=action.action_sub.value,
                label=action.label.strip(),
                sublabel=_clean_text(action.sublabel),
                content=_clean_text(action.content),
                file_media_id=action.file_media_id,
                file_name=_clean_text(action.file_name),
                file_size_bytes=action.file_size_bytes,
                url=_validate_action_url(action.url),
                sort_order=action.sort_order if action.sort_order is not None else idx,
            )
        )


def _get_or_create_tag(db: Session, name: str) -> ProjectTag:
    """标签字典 get-or-create，并发安全：两个项目同时首次用同一标签时，撞 name 唯一约束的
    那个用 SAVEPOINT 回滚（不波及外层项目插入）再重新取已存在的行——不抛 500。"""
    tag = db.scalar(select(ProjectTag).where(ProjectTag.name == name))
    if tag is not None:
        return tag
    try:
        with db.begin_nested():  # SAVEPOINT：只回滚这条 tag 插入，外层事务（项目）不受影响
            tag = ProjectTag(name=name)
            db.add(tag)
            db.flush()
        return tag
    except IntegrityError:
        return db.scalar(select(ProjectTag).where(ProjectTag.name == name))


def attach_tags(db: Session, project_id: uuid.UUID, names: List) -> None:
    """标签落表：字典表去重 + 关系表（候选 approve 与用户发布共用）。
    标签标准化：去除多余空格；**存储保留原始大小写**（"Midjourney" 不被压成 "midjourney"），
    仅在项目内**用小写做去重比较**（"AI编程"/"ai编程" 视为同一个，不重复挂）。"""
    seen = set()
    for raw in names:
        name = str(raw).strip()[:50]  # 存原文，保留大小写（前端展示不降级）
        if not name:
            continue
        key = name.lower()  # 去重用小写 key
        if key in seen:
            continue
        seen.add(key)
        tag = _get_or_create_tag(db, name)
        db.add(ProjectTagRelation(project_id=project_id, tag_id=tag.id))


def _load_attachable_media(
    db: Session, media_ids: List[uuid.UUID], current_project_id: Optional[uuid.UUID],
    uploader_user_id: uuid.UUID,
) -> List[ProjectMedia]:
    """校验 media_ids：必须全部存在，且满足其一——①已挂在当前项目上（编辑场景），或
    ②暂存态（未挂项目）**且为本人上传**。暂存媒体的归属校验杜绝跨用户挂别人的图。
    任一不过 → 422 一次性列出问题 ID。返回按入参顺序排好的媒体行。"""
    rows = {m.id: m for m in db.scalars(select(ProjectMedia).where(ProjectMedia.id.in_(media_ids)))}
    bad = []
    for mid in media_ids:
        m = rows.get(mid)
        if m is None:
            bad.append(str(mid))                                   # 不存在
        elif m.project_id is not None:
            if m.project_id != current_project_id:
                bad.append(str(mid))                               # 已被其他项目占用
        elif m.uploader_user_id != uploader_user_id:
            bad.append(str(mid))                                   # 暂存但不是本人传的——越权拦截
    if bad:
        raise AppError(422, "VALIDATION_FAILED", "media_ids 含不存在、已被其他项目使用或非本人上传的媒体",
                       {"invalid_media_ids": bad})
    return [rows[mid] for mid in media_ids]


def _mount_media(db: Session, project: Project, media_ids: List[uuid.UUID], uploader_user_id: uuid.UUID) -> None:
    """把媒体挂到项目上：按入参顺序排序，第一个作为主封面（视频用缩略图当封面）；
    原先挂着但这次没出现的退回暂存态（媒体文件回收是生产 TODO）。"""
    ordered = _load_attachable_media(db, media_ids, project.id, uploader_user_id)
    wanted = set(media_ids)
    for m in db.scalars(select(ProjectMedia).where(ProjectMedia.project_id == project.id)):
        if m.id not in wanted:
            m.project_id = None
    for i, m in enumerate(ordered):
        m.project_id = project.id
        m.sort_order = i
    first = ordered[0]
    project.cover_media_url = (first.thumbnail_url or first.url) if first.media_type == "video" else first.url


def create_user_project(db: Session, user: User, body: ProjectCreate) -> Project:
    """POST /projects：原创（user_original）与发现分享（user_discovery）都默认直接发布（PRD §11.1）。
    带 related_original_project_id 时建 similar 链并按 §5.2 通知原作者。"""
    _check_project_v2_gate(body)
    # 先校验再建项目，准入/媒体任一不过都不留半成品（含暂存媒体归属校验）
    _load_attachable_media(db, body.media_ids, None, user.id)

    related: Optional[Project] = None
    if body.related_original_project_id:
        related = db.get(Project, body.related_original_project_id)
        if related is None or related.deleted_at is not None or related.status != "published":
            raise AppError(422, "VALIDATION_FAILED", "related_original_project_id 指向的项目不存在或未发布")

    now = datetime.now(timezone.utc)
    title, tagline, summary, description = _derive_public_text(body)
    category, domains = _derive_category_domains(body)
    is_original = _is_original_from_body(body)
    project = Project(
        author_user_id=user.id,
        title=title,
        tagline=tagline,
        summary=summary,
        description=description,
        intro=_clean_text(body.intro),
        vertical=_clean_text(body.vertical),
        repo_stars=_clean_text(body.repo_stars),
        category=category,
        language=user.language_preference,  # 契约无 language 字段，跟随作者的语言偏好（补全决策）
        source_type=_source_type_from_body(body),
        is_original=is_original,
        source_url=body.source_url,
        original_author_name=body.original_author_name,
        allow_how_to_interest=body.allow_how_to_interest,
        tools=body.tools,
        domains=domains,
        ai_badge="none",  # 用户内容无 AI 编辑分；staff_pick 仅运营手动
        target_users=body.target_users,
        use_cases=body.use_cases,
        status="published",
        hot_score=0,
        published_at=now,
    )
    db.add(project)
    db.flush()

    if body.media_ids:
        _mount_media(db, project, body.media_ids, user.id)
    _create_project_actions(db, project, body)
    attach_tags(db, project.id, body.tags)

    if related is not None:
        db.add(SimilarProjectLink(source_project_id=related.id, similar_project_id=project.id))
        # §5.2：A 为平台用户原创才通知作者；外部内容只记录关联
        if related.author_user_id and related.is_original and related.author_user_id != user.id:
            db.add(
                Notification(
                    user_id=related.author_user_id,
                    type="similar_project",
                    title="有人做了类似的",
                    body=f"你的《{related.title}》有了新的类似作品《{project.title}》",
                    project_id=project.id,  # 落点：新作品详情页
                )
            )
    return project


def get_own_project(db: Session, user: User, project_id: uuid.UUID) -> Project:
    """编辑/删除前的归属校验：项目不存在或已删 → 404；不是自己的 → 403 FORBIDDEN。"""
    p = db.get(Project, project_id)
    if p is None or p.deleted_at is not None:
        raise AppError(404, "NOT_FOUND", "项目不存在")
    if p.author_user_id != user.id:
        raise AppError(403, "FORBIDDEN", "只能操作自己的项目")
    return p


def update_user_project(db: Session, user: User, project_id: uuid.UUID, body: ProjectUpdate) -> Project:
    """PATCH /projects/{id}：轻编辑直接生效（PRD §6.13；风险词转 under_review 是后台批次的事）。
    改完仍须满足发布准入，否则 409——不允许把已发布项目改成纯单图无方法。"""
    project = get_own_project(db, user, project_id)
    changes = body.model_dump(exclude_unset=True)

    final_tools = changes["tools"] if changes.get("tools") is not None else (project.tools or [])
    final_description = changes.get("description", project.description) or changes.get("intro", project.intro)
    has_actions = bool(db.scalar(select(ProjectAction.id).where(ProjectAction.project_id == project.id).limit(1)))
    if not has_actions:
        check_user_publish_gate(final_tools, final_description)

    for field, value in changes.items():
        if field in ("media_ids", "tags"):
            continue
        if value is None and field != "description":
            continue  # 除 description 可清空外，传 null 视为不修改（这些列在库里非空）
        if field == "category" and value is not None:
            project.category = value.value if hasattr(value, "value") else value
        elif field == "domains" and value is not None:
            project.domains = [d.value if hasattr(d, "value") else d for d in value]
        else:
            setattr(project, field, value)

    if "media_ids" in changes and changes["media_ids"]:
        _mount_media(db, project, body.media_ids, user.id)
    if "tags" in changes and changes["tags"] is not None:
        for rel in db.scalars(select(ProjectTagRelation).where(ProjectTagRelation.project_id == project.id)):
            db.delete(rel)
        db.flush()
        attach_tags(db, project.id, changes["tags"])
    return project


def soft_delete_project(db: Session, user: User, project_id: uuid.UUID) -> None:
    """软删（红线：删除=deleted，与下架 taken_down 是两个独立状态）：留记录，列表与详情都不可见。"""
    project = get_own_project(db, user, project_id)
    project.status = "deleted"
    project.deleted_at = datetime.now(timezone.utc)
