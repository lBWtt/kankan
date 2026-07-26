# ============================================================
# 这个文件是干什么的：后台管理动作的业务逻辑车间——已发布项目的下架/恢复/软删/要求修改/
#   精选位设置（PRD §8.4 管理员动作映射），以及举报处理的连带项目动作（后台 v1.2）。
# 它对应产品里的什么功能：运营后台"项目管理"和"举报处理"两个页面的全部按钮。
# 如果它出错了，用户会看到什么现象：违规内容下不了架、误删恢复不了、作者收不到整改通知。
# ============================================================
import uuid
from datetime import datetime, timezone
from typing import Dict, Optional, Set, Tuple

from sqlalchemy.orm import Session

from app.core.errors import AppError
from app.models import Notification, Post, Project, Report, User
from app.services.audit import log_admin_action

# 管理动作 → (允许的起始状态, 目标状态)。红线：下架 taken_down 与删除 deleted 是两个独立状态。
# restore 含 under_review（补全决策：要求修改/标记风险后的项目核查通过也要能恢复展示）。
_TRANSITIONS: Dict[str, Tuple[Set[str], str]] = {
    "take_down": ({"published", "hidden", "under_review"}, "taken_down"),
    "restore": ({"taken_down", "hidden", "under_review"}, "published"),
    "soft_delete": ({"draft", "published", "hidden", "under_review", "rejected", "taken_down"}, "deleted"),
    "require_edit": ({"published", "hidden", "under_review"}, "under_review"),
    # 标记风险：同样转 under_review 但不通知作者（后台 v1.2：先排查，查实才要求修改/下架）
    "mark_risk": ({"published", "hidden", "under_review"}, "under_review"),
}

# 动作发给作者的 content_status 通知文案（外部抓取内容无站内作者，自动跳过）
_AUTHOR_NOTICE = {
    "take_down": ("你的项目已被下架", "《{title}》已被运营下架{reason}，整改后可申请恢复"),
    "restore": ("你的项目已恢复展示", "《{title}》已恢复正常展示"),
    "soft_delete": ("你的项目已被删除", "《{title}》因违反内容规范被删除{reason}"),
    "require_edit": ("你的项目需要修改", "《{title}》需要修改后才能继续展示{reason}"),
}


def _get_admin_project(db: Session, project_id: uuid.UUID) -> Project:
    """后台视角取项目：只有真删不存在；软删的也允许查到（但不允许再操作）。"""
    p = db.get(Project, project_id)
    if p is None:
        raise AppError(404, "NOT_FOUND", "项目不存在")
    return p


def apply_project_action(
    db: Session, admin: User, project_id: uuid.UUID, action: str, reason: Optional[str]
) -> Project:
    """统一的管理动作执行：校验状态机转移 → 改状态 → 通知作者 → 留痕（同一事务）。"""
    project = _get_admin_project(db, project_id)
    allowed_from, target = _TRANSITIONS[action]
    if project.status not in allowed_from:
        raise AppError(
            409, "PROJECT_INVALID_STATE",
            f"项目当前状态为 {project.status}，不允许执行 {action}",
            {"status": project.status, "allowed_from": sorted(allowed_from)},
        )

    project.status = target
    if action == "soft_delete":
        project.deleted_at = datetime.now(timezone.utc)
    if action == "take_down":
        project.featured_rank = None  # 下架的内容不该还挂在今日精选位上

    if project.author_user_id and action in _AUTHOR_NOTICE:
        title_tpl, body_tpl = _AUTHOR_NOTICE[action]
        reason_part = f"（原因：{reason}）" if reason else ""
        db.add(
            Notification(
                user_id=project.author_user_id,
                type="content_status",
                title=title_tpl,
                body=body_tpl.format(title=project.title, reason=reason_part),
                project_id=project.id,
            )
        )

    log_admin_action(db, admin.id, f"{action}_project", "project", project.id,
                     {"reason": reason} if reason else None)
    return project


def set_featured_rank(db: Session, admin: User, project_id: uuid.UUID, rank: Optional[int]) -> Project:
    """设置/取消今日精选位：只有 published 的项目能上精选。"""
    project = _get_admin_project(db, project_id)
    if rank is not None and project.status != "published":
        raise AppError(409, "PROJECT_INVALID_STATE", "只有已发布的项目才能设为今日精选",
                       {"status": project.status})
    project.featured_rank = rank
    log_admin_action(db, admin.id, "feature_project", "project", project.id, {"featured_rank": rank})
    return project


def admin_delete_post(db: Session, admin: User, post_id: uuid.UUID) -> None:
    """管理员软删任意动态（不限本人）——用于统一管理马甲/清理违规内容。
    与 posts.delete_post 的「仅本人」不同：后台按 is_admin 授权，可删任何人的动态。幂等：已删再删也 OK。"""
    p = db.get(Post, post_id)
    if p is None:
        raise AppError(404, "NOT_FOUND", "动态不存在")
    if p.deleted_at is None:
        p.deleted_at = datetime.now(timezone.utc)
    log_admin_action(db, admin.id, "delete_post", "post", p.id, {"author_user_id": str(p.author_user_id)})


def resolve_report(
    db: Session, admin: User, report_id: uuid.UUID, result: str, project_action: str, note: Optional[str]
) -> None:
    """处理举报：记结论 + 可选连带项目动作（复用同一套状态机转移，作者通知/留痕一并触发）。"""
    report = db.get(Report, report_id)
    if report is None:
        raise AppError(404, "NOT_FOUND", "举报不存在")
    if report.status in ("resolved", "rejected"):
        raise AppError(409, "ALREADY_EXISTS", "该举报已处理过", {"status": report.status})
    if result not in ("resolved", "rejected"):
        raise AppError(422, "VALIDATION_FAILED", "result 只能是 resolved（成立）或 rejected（不成立）")

    if project_action != "ignore":
        apply_project_action(db, admin, report.project_id, project_action, note)
    # ignore：项目状态不变

    report.status = result
    report.handled_by_user_id = admin.id
    report.handled_at = datetime.now(timezone.utc)
    report.resolution_note = note
    log_admin_action(db, admin.id, "resolve_report", "report", report.id,
                     {"result": result, "project_action": project_action})
