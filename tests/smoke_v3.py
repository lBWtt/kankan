# ============================================================
# 这个文件是干什么的：后台管理 + 举报闭环 + 用户主页 + 分享卡的端到端冒烟测试——
#   把"举报→后台处理→连带下架→作者收通知→恢复"、需求看板聚合、数据看板、每日精选推送、
#   操作日志、用户主页、分享卡整套跑一遍，包括状态机非法转移 409 等该报错的场景。
# 它对应产品里的什么功能：运营后台全部页面 + 用户主页 + 分享卡。
# 如果它出错了，用户会看到什么现象：开发者会在上线前发现问题——这正是它存在的目的。
# 用法：先起服务（uvicorn app.main:app），再在 backend/ 下跑：
#   .venv/Scripts/python.exe tests/smoke_v3.py [BASE_URL，默认 http://127.0.0.1:8000]
# ============================================================
import base64
import sys
import time

import httpx
from sqlalchemy import text as sql

from app.core.db import engine

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


def publish(c, auth, marker, title_suffix, **overrides):
    r = c.post("/api/v1/media", headers=auth, files={"file": ("a.png", PNG_1PX, "image/png")})
    payload = {
        "title": f"{marker} {title_suffix}",
        "tagline": "用 AI 一晚上做出可用工具",
        "summary": "这是一段超过二十个字的项目简介，描述这个 AI 用例做了什么、为什么值得一看。",
        "description": "完整复现步骤：先用脚手架生成骨架，再接 API，最后一键部署上线。",
        "category": "automation_tools",
        "domains": ["dev"],
        "tools": ["Claude Code"],
        "media_ids": [r.json()["id"]],
        "is_original": True,
        "tags": [],
    }
    payload.update(overrides)
    r = c.post("/api/v1/projects", headers=auth, json=payload)
    assert r.status_code == 201, r.text
    return r.json()["id"]


def main():
    c = httpx.Client(base_url=BASE, timeout=30, trust_env=False)  # trust_env=False 绕过本机代理
    ts = int(time.time())
    marker = f"V3冒烟{ts % 100000}"

    print("== 0. 准备：作者 + 举报人 + 管理员，两个项目 ==")
    author_auth, author_uid = login(c, f"133{ts % 100000000:08d}")
    reporter_auth, reporter_uid = login(c, f"132{(ts + 5) % 100000000:08d}")
    admin_auth, admin_uid = login(c, f"131{(ts + 9) % 100000000:08d}")
    with engine.begin() as conn:
        conn.execute(sql("UPDATE users SET is_admin = true WHERE id = :id"), {"id": admin_uid})
    p1 = publish(c, author_auth, marker, "原创甲")
    p2 = publish(c, author_auth, marker, "原创乙")
    # 外部内容（需求看板用）：直接 SQL 造一条 ai_crawled + 想看怎么做记录
    import uuid as uuidlib
    p_ext = str(uuidlib.uuid4())
    with engine.begin() as conn:
        conn.execute(sql("""
            INSERT INTO projects (id, title, tagline, summary, category, language, source_type,
                                  is_original, tools, domains, status, published_at)
            VALUES (:id, :t, '外部内容亮点不少于五字', '这是一段超过二十个字的外部内容简介，用于需求看板聚合测试。',
                    'automation_tools', 'zh-CN', 'ai_crawled', false, ARRAY['Claude Code'], ARRAY['dev'],
                    'published', now())"""), {"id": p_ext, "t": f"{marker} 外部内容"})
    for i in range(3):
        c.post(f"/api/v1/projects/{p_ext}/how-to-interest", json={"anon_client_id": f"v3-anon-{i}"})
    c.post(f"/api/v1/projects/{p1}/how-to-interest", json={"anon_client_id": "v3-anon-0"})

    print("== 1. 后台项目管理（状态机 + 作者通知 + 留痕）==")
    r = c.get("/api/v1/admin/projects", headers=admin_auth, params={"q": marker})
    check("项目管理列表按 q 命中 3 个", r.status_code == 200 and len(r.json()["items"]) == 3, r.text[:200])
    r = c.get("/api/v1/admin/projects", headers=author_auth)
    check("非管理员调项目管理 = 403", r.status_code == 403)

    r = c.post(f"/api/v1/admin/projects/{p1}/take-down", headers=admin_auth, json={"reason": "测试下架"})
    check("下架 = 200 且状态 taken_down", r.status_code == 200 and r.json()["status"] == "taken_down", r.text)
    check("下架后对外 404（红线：≠删除）", c.get(f"/api/v1/projects/{p1}").status_code == 404)
    r = c.post(f"/api/v1/admin/projects/{p1}/take-down", headers=admin_auth, json={})
    check("重复下架 = 409 PROJECT_INVALID_STATE",
          r.status_code == 409 and r.json()["code"] == "PROJECT_INVALID_STATE", r.text)
    r = c.get("/api/v1/notifications", headers=author_auth, params={"unread_only": True})
    notes = [n for n in r.json()["items"] if n["type"] == "content_status" and n["project_id"] == p1]
    check("作者收到下架通知（含原因）", len(notes) == 1 and "测试下架" in (notes[0]["body"] or ""), str(notes))

    r = c.post(f"/api/v1/admin/projects/{p1}/restore", headers=admin_auth, json={})
    check("恢复 = 200 且状态 published", r.status_code == 200 and r.json()["status"] == "published")
    check("恢复后对外可见", c.get(f"/api/v1/projects/{p1}").status_code == 200)

    r = c.post(f"/api/v1/admin/projects/{p1}/require-edit", headers=admin_auth, json={"reason": "标题夸大"})
    check("要求修改 = 200 且状态 under_review", r.status_code == 200 and r.json()["status"] == "under_review")
    r = c.get(f"/api/v1/projects/{p1}", headers=author_auth)
    check("under_review 作者本人可见", r.status_code == 200 and r.json()["status"] == "under_review")
    r = c.post(f"/api/v1/admin/projects/{p1}/restore", headers=admin_auth, json={})
    check("整改核查后恢复 = 200", r.status_code == 200 and r.json()["status"] == "published")

    r = c.post(f"/api/v1/admin/projects/{p1}/feature", headers=admin_auth, json={"featured_rank": 1})
    check("设精选位 = 200", r.status_code == 200)
    r = c.get("/api/v1/projects", params={"section": "today_pick"})
    check("今日精选出现该项目", any(x["id"] == p1 for x in r.json()["items"]))
    r = c.post(f"/api/v1/admin/projects/{p1}/take-down", headers=admin_auth, json={})
    check("下架自动撤掉精选位", r.status_code == 200)
    with engine.connect() as conn:
        fr = conn.execute(sql("SELECT featured_rank FROM projects WHERE id=:p"), {"p": p1}).scalar()
    check("featured_rank 已清空", fr is None, f"实际 {fr}")
    c.post(f"/api/v1/admin/projects/{p1}/restore", headers=admin_auth, json={})
    r = c.post(f"/api/v1/admin/projects/{p2}/feature", headers=admin_auth, json={"featured_rank": None})
    check("feature 传 null = 取消精选（幂等 200）", r.status_code == 200)

    print("== 2. 举报闭环 ==")
    r = c.post(f"/api/v1/projects/{p2}/reports", json={"reason": "ad_spam"})
    check("游客举报 = 401（举报需登录）", r.status_code == 401)
    r = c.post(f"/api/v1/projects/{p2}/reports", headers=reporter_auth,
               json={"reason": "ad_spam", "description": "全是广告链接"})
    check("举报提交 = 201 返回 report_id", r.status_code == 201 and r.json()["report_id"], r.text)
    report_id = r.json()["report_id"]

    r = c.get("/api/v1/admin/reports", headers=admin_auth, params={"status": "pending"})
    mine = [x for x in r.json()["items"] if x["id"] == report_id]
    check("后台举报队列可见（带项目标题）", len(mine) == 1 and marker in mine[0]["project_title"], r.text[:300])

    r = c.post(f"/api/v1/admin/reports/{report_id}/resolve", headers=admin_auth,
               json={"result": "resolved", "project_action": "take_down", "note": "广告确认"})
    check("处理举报（成立+连带下架）= 200", r.status_code == 200, r.text)
    with engine.connect() as conn:
        st = conn.execute(sql("SELECT status FROM projects WHERE id=:p"), {"p": p2}).scalar()
    check("连带动作生效：项目已下架", st == "taken_down", f"实际 {st}")
    r = c.get("/api/v1/notifications", headers=author_auth, params={"unread_only": True})
    check("连带下架也给作者发了通知",
          any(n["type"] == "content_status" and n["project_id"] == p2 for n in r.json()["items"]))
    r = c.post(f"/api/v1/admin/reports/{report_id}/resolve", headers=admin_auth,
               json={"result": "rejected", "project_action": "ignore"})
    check("重复处理 = 409", r.status_code == 409)

    print("== 3. 需求看板（§5.5 只读聚合）==")
    r = c.get("/api/v1/admin/demand-board", headers=admin_auth)
    items = [x for x in r.json()["items"] if x["project_id"] == p_ext]
    check("外部内容进看板且需求数=3", len(items) == 1 and items[0]["demand_count"] == 3, r.text[:300])
    check("平台原创不进看板（p1 有需求但来源是 user_original）",
          all(x["project_id"] != p1 for x in r.json()["items"]))
    r = c.get("/api/v1/admin/demand-board", headers=admin_auth, params={"domain": "design"})
    check("domain 筛选过滤掉 dev 内容", all(x["project_id"] != p_ext for x in r.json()["items"]))

    print("== 4. 数据看板 ==")
    r = c.get("/api/v1/admin/dashboard", headers=admin_auth)
    j = r.json()
    check("dashboard = 200 且统计非负", r.status_code == 200 and j["published_projects"] >= 1, r.text[:300])
    check("想看怎么做计数来自真实子表（≥4）", j["funnel"]["how_to_interest_clicks"] >= 4, str(j["funnel"]))
    check("open_reports 不含已处理的", isinstance(j["open_reports"], int))

    print("== 5. 每日精选推送 ==")
    r = c.patch("/api/v1/me/push-preferences", headers=reporter_auth, json={"daily_pick_enabled": False})
    check("举报人关掉每日精选推送", r.status_code == 200)
    r = c.post("/api/v1/admin/push/daily-pick", headers=admin_auth, json={"project_id": p1})
    check("推送 = 200 且触达数 ≥2", r.status_code == 200 and r.json()["audience_count"] >= 2, r.text)
    audience = r.json()["audience_count"]
    r = c.get("/api/v1/notifications", headers=author_auth)
    check("作者收到 daily_pick 站内通知", any(n["type"] == "daily_pick" for n in r.json()["items"]))
    r = c.get("/api/v1/notifications", headers=reporter_auth)
    check("关了开关的人没收到", all(n["type"] != "daily_pick" for n in r.json()["items"]), f"audience={audience}")
    r = c.post("/api/v1/admin/push/daily-pick", headers=admin_auth, json={"project_id": p2})
    check("推未发布的项目 = 404（p2 已下架）", r.status_code == 404)

    print("== 6. 操作日志 ==")
    r = c.get("/api/v1/admin/actions", headers=admin_auth, params={"admin_user_id": admin_uid, "page_size": 50})
    actions = [x["action"] for x in r.json()["items"]]
    expect = {"take_down_project", "restore_project", "require_edit_project", "feature_project",
              "resolve_report", "push_daily_pick"}
    check("操作日志覆盖全部动作类型", expect.issubset(set(actions)), str(sorted(set(actions))))
    r = c.get("/api/v1/admin/actions", headers=admin_auth, params={"target_type": "report"})
    check("target_type 筛选命中 resolve_report", all(x["target_type"] == "report" for x in r.json()["items"]))

    print("== 7. 用户主页 + 分享卡 ==")
    r = c.get(f"/api/v1/users/{author_uid}")
    j = r.json()
    check("用户主页 = 200（游客可看）", r.status_code == 200, r.text[:200])
    check("不泄露手机号/邮箱等私密字段", "phone" not in j and "email" not in j, str(j))
    check("已发布作品数=1（p2 已被下架不计）", j["published_project_count"] == 1, str(j))
    r = c.get(f"/api/v1/users/{author_uid}/projects")
    check("TA 的作品只给 published", [x["id"] for x in r.json()["items"]] == [p1], r.text[:200])
    check("不存在的用户 = 404", c.get(f"/api/v1/users/{uuidlib.uuid4()}").status_code == 404)

    r = c.post(f"/api/v1/projects/{p1}/share-card")
    j = r.json()
    check("分享卡 = 200（游客可用）", r.status_code == 200, r.text[:300])
    check("share_url 指向 Web 分享页且素材齐全",
          j["share_url"].endswith(f"/p/{p1}") and j["title"] and j["counts"]["how_to_interests"] == 1, str(j)[:300])
    check("下架的项目不出分享卡", c.post(f"/api/v1/projects/{p2}/share-card").status_code == 404)

    # ---- 清理本次测试数据（保持 dev 库干净）----
    pids_sub = ("(SELECT id FROM projects WHERE author_user_id = ANY(CAST(:u AS uuid[])) "
                "UNION SELECT CAST(:pe AS uuid))")
    params = {"u": created_user_ids, "pe": p_ext}
    with engine.begin() as conn:
        for t in ("notifications", "how_to_interests", "favorites", "try_items", "project_reactions",
                  "clue_subscriptions", "shares", "reports", "project_media", "project_tag_relations"):
            conn.execute(sql(f"DELETE FROM {t} WHERE project_id IN {pids_sub}"), params)
        conn.execute(sql("DELETE FROM notifications WHERE user_id = ANY(CAST(:u AS uuid[]))"),
                     {"u": created_user_ids})
        conn.execute(sql(f"DELETE FROM admin_actions WHERE target_id IN {pids_sub} "
                         "OR admin_user_id = ANY(CAST(:u AS uuid[]))"), params)
        conn.execute(sql(f"DELETE FROM projects WHERE id IN {pids_sub}"), params)
        conn.execute(sql("DELETE FROM push_preferences WHERE user_id = ANY(CAST(:u AS uuid[]))"),
                     {"u": created_user_ids})
        conn.execute(sql("DELETE FROM users WHERE id = ANY(CAST(:u AS uuid[]))"), {"u": created_user_ids})

    print(f"\n结果：{passed} 通过 / {failed} 失败")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
