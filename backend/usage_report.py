# ============================================================
# 这个文件是干什么的：命令行「使用情况 + 反馈」速览——一条命令看：到底有没有人用（DAU/活跃清单/
#   是不是就管理员自己）、最近的意见反馈。给独立开发者上线后快速判断"是不是我们俩自嗨"。
# 用法（backend/ 下）：
#   python usage_report.py            # 近 7 天
#   python usage_report.py --days 30
# 对应后台接口 GET /admin/usage、GET /admin/feedback（这里直连库，免登录，方便本地看）。
# ============================================================
import argparse
from datetime import datetime, timedelta, timezone

from sqlalchemy import func, select

from app.core.db import SessionLocal
from app.models import AnalyticsEvent, Feedback, User


def main() -> None:
    ap = argparse.ArgumentParser(description="使用情况 + 反馈速览")
    ap.add_argument("--days", type=int, default=7)
    args = ap.parse_args()

    now = datetime.now(timezone.utc)
    start = now - timedelta(days=args.days)
    today_start = datetime(now.year, now.month, now.day, tzinfo=timezone.utc)
    real_user = ~func.coalesce(User.email, "").like("%@persona.kankan")

    with SessionLocal() as db:
        total = db.scalar(select(func.count()).select_from(User)
                          .where(User.deleted_at.is_(None), real_user)) or 0
        new = db.scalar(select(func.count()).select_from(User)
                        .where(User.deleted_at.is_(None), real_user, User.created_at >= start)) or 0
        active = db.scalar(select(func.count(func.distinct(AnalyticsEvent.user_id)))
                           .where(AnalyticsEvent.user_id.isnot(None), AnalyticsEvent.created_at >= start)) or 0
        dau = db.scalar(select(func.count(func.distinct(AnalyticsEvent.user_id)))
                        .where(AnalyticsEvent.user_id.isnot(None), AnalyticsEvent.created_at >= today_start)) or 0
        admin_active = db.scalar(
            select(func.count(func.distinct(AnalyticsEvent.user_id)))
            .select_from(AnalyticsEvent).join(User, User.id == AnalyticsEvent.user_id)
            .where(User.is_admin.is_(True), AnalyticsEvent.created_at >= start)) or 0
        guest_opens = db.scalar(
            select(func.count()).select_from(AnalyticsEvent)
            .where(AnalyticsEvent.user_id.is_(None), AnalyticsEvent.event_name == "app_open",
                   AnalyticsEvent.created_at >= start)) or 0

        print("=" * 60)
        print(f"使用情况 · 近 {args.days} 天（{start.date()} ~ {now.date()}）")
        print("=" * 60)
        print(f"真实用户总数：{total}   新增：{new}")
        print(f"活跃用户(有行为)：{active}   其中管理员：{admin_active}   今日DAU：{dau}")
        print(f"游客打开次数：{guest_opens}")
        if active <= admin_active:
            print(">> 提醒：活跃用户里除了管理员没有别人——目前还是自嗨状态。")
        else:
            print(f">> 有 {active - admin_active} 个非管理员真实用户在用。")

        rows = db.execute(
            select(AnalyticsEvent.user_id, func.count().label("c"),
                   func.max(AnalyticsEvent.created_at).label("last"))
            .where(AnalyticsEvent.user_id.isnot(None), AnalyticsEvent.created_at >= start)
            .group_by(AnalyticsEvent.user_id)
            .order_by(func.max(AnalyticsEvent.created_at).desc()).limit(30)).all()
        users = {u.id: u for u in db.scalars(select(User).where(User.id.in_([r.user_id for r in rows])))} if rows else {}
        print("\n活跃用户清单（最近在前）：")
        for r in rows:
            u = users.get(r.user_id)
            tag = "管理员" if (u and u.is_admin) else "用户"
            name = u.nickname if u else str(r.user_id)[:8]
            print(f"  [{tag}] {name:<16} 行为 {r.c:>4} 次   最近 {r.last:%m-%d %H:%M}")

        print("\n" + "=" * 60)
        print("最近反馈（未处理在前）：")
        print("=" * 60)
        fbs = db.scalars(
            select(Feedback).order_by(Feedback.status.desc(), Feedback.created_at.desc()).limit(20)).all()
        if not fbs:
            print("  （暂无反馈）")
        cat_cn = {"bug": "故障", "suggestion": "建议", "other": "其他"}
        for f in fbs:
            u = db.get(User, f.user_id) if f.user_id else None
            who = u.nickname if u else "游客"
            mark = "●未处理" if f.status == "new" else "○已处理"
            print(f"  {mark} [{cat_cn.get(f.category, f.category)}] {who} · {f.platform or '?'} {f.app_version or ''}")
            print(f"        {f.content.strip()[:80]}")


if __name__ == "__main__":
    main()
