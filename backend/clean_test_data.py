# ============================================================
# 上线前清测试足迹：删掉开发期的测试账号 + 它们的埋点/反馈/垃圾内容，让运营数据从 0 起。
# 用户 2026-07-26：上线前清测试数据。
#
# 关键：测试号名下有**真实内容**（seed 项目、动态），不能直接删号（projects 会变无主、posts 会连删）。
#   所以先把真实内容**改派给马甲**（延续"马甲发布"策略），垃圾动态(jhkfkj)留着随号级联删。
#
# 处理对象 = 全部**非马甲**用户（马甲 @persona.kankan 一律保留）。
# 删号会级联清掉其评论/点赞/收藏/关注/推送偏好等（外键 CASCADE）；
#   埋点(analytics_events 无外键)、admin_actions(RESTRICT)、feedbacks(SET NULL) 手动清。
#
# ⚠️ 删号会把测试管理员一起删掉——生产登录 dev 码已失效，记得用 make_admin.py 把你的真手机号设为管理员。
#
# 跑：python clean_test_data.py            # 预览（dry-run，不动库）
#     python clean_test_data.py --apply    # 落库
# ============================================================
import re
import sys

from sqlalchemy import delete, select, text

from app.core.db import SessionLocal
from app.models import (
    AdminAction, Comment, Feedback, Post, Project, User,
)
from app.services.personas import is_persona, persona_users
from app.services.personas import pick_persona_for

_CJK = re.compile(r"[一-鿿]")
_TEST_MARKERS = ("联调", "测试", "KKK", "www点", "??????", "hhhh")


def _has_marker(s: str) -> bool:
    s = s or ""
    low = s.lower()
    return any(m in s or m.lower() in low for m in _TEST_MARKERS)


def _real_project(p) -> bool:
    """真项目：有工具标签(tools) 且标题无测试标记。垃圾测试项目 tools 为空/标题是 KKK/www点/联调测试。"""
    return bool(p.tools) and not _has_marker(p.title or "")


def _looks_real_post(text_: str) -> bool:
    return len(_CJK.findall(text_ or "")) >= 4 and not _has_marker(text_ or "")


def main() -> None:
    apply = "--apply" in sys.argv
    db = SessionLocal()
    try:
        all_users = db.scalars(select(User)).all()
        personas = persona_users(db)
        test_users = [u for u in all_users if not is_persona(u)]
        if not personas:
            print("没有马甲可改派，先跑 seed_personas.py"); return
        if not test_users:
            print("没有测试账号，无需清理"); return
        tids = [u.id for u in test_users]

        # 1) 测试号名下的项目：真的改派给马甲，垃圾的直接删（否则删号后变无主但仍发布）
        projs = db.scalars(select(Project).where(Project.author_user_id.in_(tids))).all()
        reassigned_proj = deleted_proj = 0
        for p in projs:
            if _real_project(p):
                persona = pick_persona_for(db, category=p.category, domains=list(p.domains or [])) \
                    or personas[0]
                if not apply:
                    print(f"  项目改派《{p.title[:24]}》→ {persona.nickname}")
                else:
                    p.author_user_id = persona.id
                reassigned_proj += 1
            else:
                if not apply:
                    print(f"  删垃圾项目《{p.title[:24]}》")
                else:
                    db.delete(p)
                deleted_proj += 1

        # 2) 改派测试号的**真实**动态 → 马甲；垃圾动态留着随号级联删
        posts = db.scalars(select(Post).where(Post.author_user_id.in_(tids))).all()
        reassigned_post = junk_post = 0
        for po in posts:
            if _looks_real_post(po.content):
                persona = pick_persona_for(db) or personas[0]
                if apply:
                    po.author_user_id = persona.id
                reassigned_post += 1
            else:
                junk_post += 1  # 随用户删除级联清掉

        # 3) 手动清 RESTRICT / 无外键 / SET NULL 的关联
        n_admin_act = len(db.scalars(select(AdminAction.id).where(AdminAction.admin_user_id.in_(tids))).all())
        n_feedback = len(db.scalars(select(Feedback.id).where(Feedback.user_id.in_(tids))).all())
        # analytics_events 无 ORM 外键，用原生 SQL 按 user_id 删
        n_events = db.scalar(text("SELECT count(*) FROM analytics_events WHERE user_id = ANY(:ids)"),
                             {"ids": tids}) or 0

        print(f"\n将清理：测试账号 {len(test_users)} 个")
        print(f"  改派真实项目 {reassigned_proj}、删垃圾项目 {deleted_proj}")
        print(f"  改派真实动态 {reassigned_post}、级联删垃圾动态 {junk_post}")
        print(f"  删埋点事件 {n_events}、admin_actions {n_admin_act}、feedbacks {n_feedback}")
        print("  级联清：这些号的评论/点赞/收藏/关注/推送偏好等")

        if not apply:
            print("\n[dry-run] 加 --apply 落库。⚠️ 会删测试管理员——生产记得 make_admin.py 设真管理员。")
            return

        db.flush()  # 落定改派，避免删号时 projects 变 NULL / posts 连删
        db.execute(delete(AdminAction).where(AdminAction.admin_user_id.in_(tids)))
        db.execute(delete(Feedback).where(Feedback.user_id.in_(tids)))
        db.execute(text("DELETE FROM analytics_events WHERE user_id = ANY(:ids)"), {"ids": tids})
        db.execute(delete(User).where(User.id.in_(tids)))  # 级联清其余
        db.commit()

        remain = db.scalar(text("SELECT count(*) FROM users WHERE email IS NULL OR email NOT LIKE '%@persona.kankan'"))
        print(f"\n完成。非马甲用户剩余：{remain}（应为 0）。上线运营数据从干净起。")
    finally:
        db.close()


if __name__ == "__main__":
    main()
