# ============================================================
# 这个文件是干什么的：埋点上报 + 定时任务的端到端冒烟测试——验证事件批量入库、
#   异常时间钟修正、事件喂进 dashboard 漏斗和 hot_score 浏览权重，
#   以及直接调用任务函数验证榜单全量校准和孤儿媒体回收。
# 它对应产品里的什么功能：数据看板漏斗、本周热门的新鲜度、磁盘不被废弃上传塞满。
# 如果它出错了，用户会看到什么现象：开发者会在上线前发现问题——这正是它存在的目的。
# 用法：先起服务（uvicorn app.main:app），再在 backend/ 下跑：
#   .venv/Scripts/python.exe tests/smoke_v4.py [BASE_URL，默认 http://127.0.0.1:8000]
# ============================================================
import base64
import os
import sys
import time
import uuid as uuidlib
from datetime import datetime, timedelta, timezone

import httpx
from sqlalchemy import text as sql

from app.core.config import settings
from app.core.db import SessionLocal, engine
from app.core.redis import redis_client
from app.services.maintenance import purge_staged_media
from app.services.rankings import calibrate_hot_scores

BASE = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8000"
PNG_1PX = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
)

passed, failed = 0, 0
created_user_ids = []


def check(name: str, cond: bool, extra=""):
    global passed, failed
    if cond:
        passed += 1
        print(f"  PASS  {name}")
    else:
        failed += 1
        print(f"  FAIL  {name}  {extra}")


def login(c, phone):
    r = c.post("/api/v1/auth/login", json={"identifier_type": "phone", "identifier": phone, "code": "888888"})
    assert r.status_code == 200, r.text
    j = r.json()
    created_user_ids.append(j["user"]["id"])
    return {"Authorization": f"Bearer {j['access_token']}"}, j["user"]["id"]


def main():
    c = httpx.Client(base_url=BASE, timeout=30, trust_env=False)  # trust_env=False 绕过本机代理
    ts = int(time.time())
    marker = f"V4冒烟{ts % 100000}"

    print("== 0. 准备：管理员 + 一个已发布项目 ==")
    admin_auth, admin_uid = login(c, f"130{ts % 100000000:08d}")
    with engine.begin() as conn:
        conn.execute(sql("UPDATE users SET is_admin = true WHERE id = :id"), {"id": admin_uid})
    pid = str(uuidlib.uuid4())
    with engine.begin() as conn:
        conn.execute(sql("""
            INSERT INTO projects (id, title, tagline, summary, category, language, source_type,
                                  is_original, tools, domains, status, published_at)
            VALUES (:id, :t, '埋点测试项目亮点五字', '这是一段超过二十个字的项目简介，用于埋点与定时任务冒烟测试。',
                    'automation_tools', 'zh-CN', 'ai_crawled', false, ARRAY['Claude Code'], ARRAY['dev'],
                    'published', now())"""), {"id": pid, "t": f"{marker} 埋点项目"})

    print("== 1. 埋点上报（POST /events）==")
    r = c.post("/api/v1/events", json={"events": []})
    check("空批 = 422", r.status_code == 422)
    r = c.post("/api/v1/events", json={"events": [{"event_name": "BadName"}]})
    check("非 snake_case 事件名 = 422", r.status_code == 422)
    r = c.post("/api/v1/events", json={"events": [{"event_name": "card_click"}] * 51})
    check("超过 50 条 = 422", r.status_code == 422)

    batch = {
        "events": [
            {"event_name": "card_impression", "project_id": pid},
            {"event_name": "card_impression", "project_id": pid},
            {"event_name": "detail_view", "project_id": pid},
            {"event_name": "search_query", "payload": {"q": "AI 工具"}},
        ],
        "client_info": {"anon_client_id": "v4-anon", "app_version": "0.1.0"},
    }
    r = c.post("/api/v1/events", json=batch)
    check("游客批量上报 = 201 accepted=4", r.status_code == 201 and r.json()["accepted"] == 4, r.text)
    r = c.post("/api/v1/events", json={"events": [{"event_name": "detail_view", "project_id": pid}]},
               headers=admin_auth)
    check("登录上报 = 201（自动带 user_id）", r.status_code == 201)
    with engine.connect() as conn:
        uid_in_db = conn.execute(sql(
            "SELECT user_id FROM analytics_events WHERE event_name='detail_view' AND project_id=:p "
            "AND user_id IS NOT NULL LIMIT 1"), {"p": pid}).scalar()
    check("登录事件 user_id 落库", str(uid_in_db) == admin_uid, f"实际 {uid_in_db}")

    future = (datetime.now(timezone.utc) + timedelta(days=3)).isoformat()
    r = c.post("/api/v1/events", json={"events": [
        {"event_name": "app_open", "occurred_at": future},
        {"event_name": "app_open", "occurred_at": "2020-01-01T00:00:00Z"},
    ]})
    check("异常时间（未来/太久前）也接收 = 201", r.status_code == 201 and r.json()["accepted"] == 2)
    with engine.connect() as conn:
        n_bad = conn.execute(sql(
            "SELECT count(*) FROM analytics_events WHERE event_name='app_open' "
            "AND (created_at > now() + interval '10 minutes' OR created_at < now() - interval '8 days')"
        )).scalar()
    check("异常时间已被修正为服务端时间（无未来/古董记录）", n_bad == 0, f"实际 {n_bad}")

    print("== 2. 事件喂进 dashboard 漏斗 ==")
    r = c.get("/api/v1/admin/dashboard", headers=admin_auth)
    f = r.json()["funnel"]
    check("card_impressions ≥2 / detail_views ≥2", f["card_impressions"] >= 2 and f["detail_views"] >= 2, str(f))

    print("== 3. 事件喂进 hot_score（view×1 + detail_click×2）==")
    try:
        redis_client.delete("rankings:weekly_hot")
    except Exception:
        pass
    r = c.get("/api/v1/rankings", params={"type": "weekly_hot", "limit": 100})
    ranked = [x["project"]["id"] for x in r.json()["items"]]
    check("纯埋点行为（无互动）也能上榜", pid in ranked, str(ranked)[:200])
    with engine.connect() as conn:
        hs = conn.execute(sql("SELECT hot_score FROM projects WHERE id=:p"), {"p": pid}).scalar()
    # 2×card_impression×1 + 2×detail_view×2 = 6，衰减后略小
    check("hot_score ≈6（2 曝光 + 2 详情）", hs is not None and 5 < hs <= 6.1, f"实际 {hs}")

    print("== 4. 定时任务：榜单全量校准 ==")
    with engine.begin() as conn:  # 伪造一个"行为早已衰减干净但分数还挂着"的老项目
        stale = str(uuidlib.uuid4())
        conn.execute(sql("""
            INSERT INTO projects (id, title, tagline, summary, category, language, source_type,
                                  is_original, tools, domains, status, published_at, hot_score)
            VALUES (:id, :t, '过气项目亮点不少五字', '这是一段超过二十个字的项目简介，行为早衰减完但分数还挂着。',
                    'automation_tools', 'zh-CN', 'ai_crawled', false, ARRAY['Claude Code'], ARRAY['dev'],
                    'published', now() - interval '30 days', 99.9)"""),
            {"id": stale, "t": f"{marker} 过气项目"})
    with SessionLocal() as db:
        updated = calibrate_hot_scores(db)
    check("全量校准跑通且有更新", updated >= 1, f"更新 {updated} 条")
    with engine.connect() as conn:
        hs_stale = conn.execute(sql("SELECT hot_score FROM projects WHERE id=:p"), {"p": stale}).scalar()
        hs_live = conn.execute(sql("SELECT hot_score FROM projects WHERE id=:p"), {"p": pid}).scalar()
    check("无行为的老项目分数归零", hs_stale == 0, f"实际 {hs_stale}")
    check("有行为的项目分数保留", hs_live and hs_live > 5, f"实际 {hs_live}")

    print("== 5. 定时任务：孤儿媒体回收 ==")
    r = c.post("/api/v1/media", headers=admin_auth, files={"file": ("a.png", PNG_1PX, "image/png")})
    fresh_id, fresh_url = r.json()["id"], r.json()["url"]
    r = c.post("/api/v1/media", headers=admin_auth, files={"file": ("b.png", PNG_1PX, "image/png")})
    old_id, old_url = r.json()["id"], r.json()["url"]
    with engine.begin() as conn:  # 把第二个改成 3 天前上传的
        conn.execute(sql("UPDATE project_media SET created_at = now() - interval '3 days' WHERE id = :m"),
                     {"m": old_id})
    # 从本文件位置推导 backend 根目录（原来写死 F:/ccpjv2/backend，仓库搬家/换机即失效）。
    # 前提：uvicorn 与本测试从同一个 backend/ 目录跑（upload_dir 是相对路径）。
    _backend_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    old_path = os.path.join(_backend_root, settings.upload_dir, old_url.split("/uploads/")[1])
    fresh_path = os.path.join(_backend_root, settings.upload_dir, fresh_url.split("/uploads/")[1])
    with SessionLocal() as db:
        purged = purge_staged_media(db)
    check("回收跑通且清掉 ≥1 条", purged >= 1, f"清理 {purged} 条")
    with engine.connect() as conn:
        old_row = conn.execute(sql("SELECT 1 FROM project_media WHERE id=:m"), {"m": old_id}).scalar()
        fresh_row = conn.execute(sql("SELECT 1 FROM project_media WHERE id=:m"), {"m": fresh_id}).scalar()
    check("3 天前的暂存媒体：行已删", old_row is None)
    check("3 天前的暂存媒体：文件已删", not os.path.exists(old_path), old_path)
    check("刚上传的暂存媒体：行还在", fresh_row == 1)
    check("刚上传的暂存媒体：文件还在", os.path.exists(fresh_path))

    # ---- 清理本次测试数据（保持 dev 库干净）----
    with engine.begin() as conn:
        conn.execute(sql("DELETE FROM analytics_events WHERE project_id IN (CAST(:p AS uuid), CAST(:s AS uuid))"),
                     {"p": pid, "s": stale})
        conn.execute(sql("DELETE FROM analytics_events WHERE event_name IN ('search_query','app_open') "
                         "AND created_at > now() - interval '1 hour'"))
        conn.execute(sql("DELETE FROM project_media WHERE id = :m"), {"m": fresh_id})
        conn.execute(sql("DELETE FROM projects WHERE id IN (CAST(:p AS uuid), CAST(:s AS uuid))"),
                     {"p": pid, "s": stale})
        conn.execute(sql("DELETE FROM push_preferences WHERE user_id = ANY(CAST(:u AS uuid[]))"),
                     {"u": created_user_ids})
        conn.execute(sql("DELETE FROM users WHERE id = ANY(CAST(:u AS uuid[]))"), {"u": created_user_ids})
    try:
        os.remove(fresh_path)
        redis_client.delete("rankings:weekly_hot")
    except Exception:
        pass

    print(f"\n结果：{passed} 通过 / {failed} 失败")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
