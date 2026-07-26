# ============================================================
# 一次性脚本：把「现有马甲内容」的作者按人设重新打散到全部 50 个马甲。
#   非破坏：只改 author_user_id，不下架、不删、不改内容本身。
#   项目按 category/domains 智能匹配人设；动态无分类 → 按负载均衡铺开。
#   逐条 flush，让负载均衡看到实时分布 → 均匀分散。
#
# 跑：python redispatch_personas.py
# 用途：马甲从 5 扩到 50 后，让老内容立刻不再"来去就那几张脸"。真实用户内容不受影响。
# ============================================================
from collections import Counter

from sqlalchemy import select

from app.core.db import SessionLocal
from app.models import Post, Project
from app.services.personas import persona_users, pick_persona_for


def main() -> None:
    db = SessionLocal()
    try:
        personas = persona_users(db)
        persona_ids = {u.id for u in personas}
        name_by_id = {u.id: u.nickname for u in personas}
        if not persona_ids:
            print("没有马甲，跳过")
            return

        proj_moved = 0
        projects = db.scalars(
            select(Project).where(
                Project.author_user_id.in_(persona_ids), Project.deleted_at.is_(None)
            )
        ).all()
        for p in projects:
            new = pick_persona_for(db, category=p.category, domains=p.domains)
            if new is not None and new.id != p.author_user_id:
                p.author_user_id = new.id
                proj_moved += 1
            db.flush()  # 负载均衡实时更新

        post_moved = 0
        posts = db.scalars(
            select(Post).where(
                Post.author_user_id.in_(persona_ids), Post.deleted_at.is_(None)
            )
        ).all()
        for po in posts:
            new = pick_persona_for(db, category=None, domains=None)  # 动态无分类，按负载铺开
            if new is not None and new.id != po.author_user_id:
                po.author_user_id = new.id
                post_moved += 1
            db.flush()

        db.commit()

        # 重派后分布抽样
        dist = Counter()
        for p in db.scalars(
            select(Project).where(Project.author_user_id.in_(persona_ids), Project.deleted_at.is_(None))
        ):
            dist[name_by_id.get(p.author_user_id, "?")] += 1
        for po in db.scalars(
            select(Post).where(Post.author_user_id.in_(persona_ids), Post.deleted_at.is_(None))
        ):
            dist[name_by_id.get(po.author_user_id, "?")] += 1
        authors_used = len(dist)
        print(f"重派完成：项目 {proj_moved}、动态 {post_moved}")
        print(f"现在内容分布在 {authors_used} 个马甲上（共 {len(persona_ids)} 个）；每个 1~{max(dist.values()) if dist else 0} 条")
    finally:
        db.close()


if __name__ == "__main__":
    main()
