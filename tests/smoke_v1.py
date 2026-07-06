# ============================================================
# 这个文件是干什么的：V1 主信号链路的端到端冒烟测试——对着真实运行的服务和数据库，
#   把"想看怎么做（含游客）→ 需求路由通知 → 线索页 → 订阅 → 收藏/想试/反馈 → 榜单 → 通知中心"
#   整条链跑一遍，包括各种该报错的场景（红线：游客主信号绝不设登录墙）。
# 它对应产品里的什么功能：验证产品核心假设的整条数据通路行为正确。
# 如果它出错了，用户会看到什么现象：开发者会在上线前发现问题——这正是它存在的目的。
# 用法：先起服务（uvicorn app.main:app），再在 backend/ 下跑：
#   .venv/Scripts/python.exe tests/smoke_v1.py [BASE_URL，默认 http://127.0.0.1:8000]
# ============================================================
import sys
import time
import uuid as uuidlib

import httpx
from sqlalchemy import text as sql

from app.core.db import engine
from app.core.redis import redis_client

BASE = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8000"

passed, failed = 0, 0
created_project_ids, created_user_ids = [], []


def check(name: str, cond: bool, extra=""):
    global passed, failed
    if cond:
        passed += 1
        print(f"  PASS  {name}")
    else:
        failed += 1
        print(f"  FAIL  {name}  {extra}")


def login(c, phone) -> tuple:
    r = c.post("/api/v1/auth/login", json={"identifier_type": "phone", "identifier": phone, "code": "888888"})
    assert r.status_code == 200, r.text
    j = r.json()
    created_user_ids.append(j["user"]["id"])
    return {"Authorization": f"Bearer {j['access_token']}"}, j["user"]["id"]


def insert_project(conn, *, title, author_uid=None, is_original=False, source_type="ai_crawled",
                   allow_how_to=True, hours_ago=0) -> str:
    pid = str(uuidlib.uuid4())
    conn.execute(
        sql("""
        INSERT INTO projects
          (id, author_user_id, title, tagline, summary, description, category, language, source_type,
           is_original, allow_how_to_interest, tools, domains, status, published_at)
        VALUES
          (:id, :author, :title, '用 AI 一晚上做出可用工具', :summary, '完整复现步骤：搭骨架、接 API、部署。',
           'automation_tools', 'zh-CN', :stype, :orig, :allow, ARRAY['Claude Code'], ARRAY['dev'],
           'published', now() - make_interval(hours => :ago))
        """),
        {"id": pid, "author": author_uid, "title": title, "stype": source_type,
         "summary": "这是一段超过二十个字的项目简介，描述这个 AI 用例做了什么、为什么值得一看。",
         "orig": is_original, "allow": allow_how_to, "ago": hours_ago},
    )
    created_project_ids.append(pid)
    return pid


def main():
    c = httpx.Client(base_url=BASE, timeout=15, trust_env=False)  # trust_env=False 绕过本机代理
    ts = int(time.time())
    marker = f"V1冒烟{ts % 100000}"

    print("== 0. 准备：两个用户 + 三个种子项目 ==")
    author_auth, author_uid = login(c, f"137{ts % 100000000:08d}")
    actor_auth, actor_uid = login(c, f"136{(ts + 7) % 100000000:08d}")
    with engine.begin() as conn:
        p1 = insert_project(conn, title=f"{marker} 平台原创", author_uid=author_uid,
                            is_original=True, source_type="user_original", hours_ago=0)
        p2 = insert_project(conn, title=f"{marker} 外部抓取", hours_ago=1)
        p3 = insert_project(conn, title=f"{marker} 关闭想看", allow_how_to=False, hours_ago=2)
    check("种子项目就绪", bool(p1 and p2 and p3))

    print("== 1. 想看怎么做（主信号，红线：游客无登录墙）==")
    r = c.post(f"/api/v1/projects/{p1}/how-to-interest", json={})
    check("游客缺 anon_client_id = 422 ANON_ID_REQUIRED",
          r.status_code == 422 and r.json()["code"] == "ANON_ID_REQUIRED", r.text)
    r = c.post(f"/api/v1/projects/{p1}/how-to-interest", json={"anon_client_id": "smoke-anon-1"})
    check("游客触发 = 201 计数 1", r.status_code == 201 and r.json()["how_to_interest_count"] == 1, r.text)
    r = c.post(f"/api/v1/projects/{p1}/how-to-interest", json={"anon_client_id": "smoke-anon-1"})
    check("同游客重复点按幂等（计数仍 1）", r.status_code == 201 and r.json()["how_to_interest_count"] == 1)
    r = c.post(f"/api/v1/projects/{p1}/how-to-interest", json={"anon_client_id": "smoke-anon-2"})
    check("第二个游客 = 计数 2", r.json()["how_to_interest_count"] == 2)
    r = c.post(f"/api/v1/projects/{p1}/how-to-interest", json={}, headers=actor_auth)
    check("登录用户触发 = 计数 3（服务端取 token 身份）", r.json()["how_to_interest_count"] == 3)
    r = c.post(f"/api/v1/projects/{p3}/how-to-interest", json={"anon_client_id": "smoke-anon-1"})
    check("项目关闭想看 = 409 HOW_TO_DISABLED",
          r.status_code == 409 and r.json()["code"] == "HOW_TO_DISABLED", r.text)
    r = c.post(f"/api/v1/projects/{uuidlib.uuid4()}/how-to-interest", json={"anon_client_id": "x"})
    check("不存在的项目 = 404", r.status_code == 404)

    print("== 2. 需求路由（§5.1：平台原创→作者通知，每日 1 条聚合）==")
    r = c.get("/api/v1/notifications", headers=author_auth, params={"unread_only": True})
    items = [n for n in r.json()["items"] if n["project_id"] == p1]
    check("作者收到 1 条 how_to_interest 通知（3 次触发聚合为 1 条）",
          len(items) == 1 and items[0]["type"] == "how_to_interest", r.text[:300])
    check("通知正文展示实际累计数 3", "3" in (items[0]["body"] or ""), str(items[0]))
    notif_id = items[0]["id"]

    r = c.patch(f"/api/v1/notifications/{notif_id}/read", headers=author_auth)
    check("作者标记已读 = 200", r.status_code == 200)
    r = c.get("/api/v1/notifications", headers=author_auth, params={"unread_only": True})
    check("已读后未读列表为空", all(n["project_id"] != p1 for n in r.json()["items"]))
    r = c.patch(f"/api/v1/notifications/{notif_id}/read", headers=actor_auth)
    check("标别人的通知 = 404（不暴露存在性）", r.status_code == 404)

    c.post(f"/api/v1/projects/{p1}/how-to-interest", json={"anon_client_id": "smoke-anon-3"})
    r = c.get("/api/v1/notifications", headers=author_auth, params={"unread_only": True})
    items = [n for n in r.json()["items"] if n["project_id"] == p1]
    check("当日新需求：同一条通知更新计数并恢复未读（仍只有 1 条）",
          len(items) == 1 and "4" in (items[0]["body"] or ""), str(items))

    r = c.post(f"/api/v1/projects/{p1}/how-to-interest", json={}, headers=author_auth)
    check("作者点自己的项目计入计数（5）", r.json()["how_to_interest_count"] == 5)
    r = c.get("/api/v1/notifications", headers=author_auth)
    n_all = [n for n in r.json()["items"] if n["project_id"] == p1]
    check("但不通知自己（通知仍 1 条、正文未变 4）", len(n_all) == 1 and "4" in (n_all[0]["body"] or ""))
    r = c.post(f"/api/v1/projects/{p2}/how-to-interest", json={"anon_client_id": "smoke-anon-1"})
    check("外部内容触发 = 201（汇入需求看板，不产生作者通知）", r.status_code == 201)
    r = c.get("/api/v1/notifications", headers=author_auth, params={"cursor": "!!!bad!!!"})
    check("通知坏 cursor = 422", r.status_code == 422)

    print("== 3. 实现线索页 + 订阅 ==")
    with engine.begin() as conn:  # P1 的"类似作品"：手工建一条关联（POST /projects 在下一轮）
        conn.execute(sql(
            "INSERT INTO similar_project_links (source_project_id, similar_project_id) VALUES (:a, :b)"),
            {"a": p1, "b": p2})
    r = c.get(f"/api/v1/projects/{p1}/implementation-clue")
    j = r.json()
    check("游客读线索页 = 200", r.status_code == 200, r.text[:200])
    check("线索页计数 = 5、is_subscribed=false、工具齐全",
          j["how_to_interest_count"] == 5 and j["is_subscribed"] is False and j["tools"] == ["Claude Code"], str(j)[:300])
    related_ids = [x["id"] for x in j["related_projects"]]
    check("关联推荐：类似作品 P2 排第一且不含自己", related_ids and related_ids[0] == p2 and p1 not in related_ids,
          str(related_ids))
    r = c.get(f"/api/v1/projects/{p1}/similar")
    check("类似作品接口返回 P2", [x["id"] for x in r.json()["items"]] == [p2], r.text[:200])

    r = c.post(f"/api/v1/projects/{p1}/clue-subscription")
    check("游客订阅 = 401（订阅需登录）", r.status_code == 401)
    r = c.post(f"/api/v1/projects/{p1}/clue-subscription", headers=actor_auth)
    check("登录订阅 = 201", r.status_code == 201, r.text)
    r = c.post(f"/api/v1/projects/{p1}/clue-subscription", headers=actor_auth)
    check("重复订阅幂等 = 201", r.status_code == 201)
    r = c.get(f"/api/v1/projects/{p1}/implementation-clue", headers=actor_auth)
    check("订阅后线索页 is_subscribed=true", r.json()["is_subscribed"] is True)
    r = c.delete(f"/api/v1/projects/{p1}/clue-subscription", headers=actor_auth)
    check("取消订阅 = 204", r.status_code == 204)
    r = c.get(f"/api/v1/projects/{p1}/implementation-clue", headers=actor_auth)
    check("取消后 is_subscribed=false", r.json()["is_subscribed"] is False)

    print("== 4. 收藏 / 想试 / 创意反馈 ==")
    check("游客收藏 = 401", c.post(f"/api/v1/projects/{p1}/favorite").status_code == 401)
    r = c.post(f"/api/v1/projects/{p1}/favorite", headers=actor_auth)
    check("收藏 = 201", r.status_code == 201)
    r = c.post(f"/api/v1/projects/{p1}/favorite", headers=actor_auth)
    check("重复收藏幂等 = 201", r.status_code == 201)
    r = c.post(f"/api/v1/projects/{p2}/favorite", headers=actor_auth)
    check("收藏第二个项目 = 201", r.status_code == 201)

    r = c.get("/api/v1/me/favorites", headers=actor_auth)
    ids = [x["id"] for x in r.json()["items"]]
    check("我的收藏：2 条且后收藏的在前", ids == [p2, p1], str(ids))
    r = c.get("/api/v1/me/favorites", headers=actor_auth, params={"page_size": 1})
    j = r.json()
    check("收藏分页：第1页 1 条且 has_more", len(j["items"]) == 1 and j["has_more"] and j["next_cursor"])
    r = c.get("/api/v1/me/favorites", headers=actor_auth, params={"page_size": 1, "cursor": j["next_cursor"]})
    check("收藏翻页：第2页是 P1", [x["id"] for x in r.json()["items"]] == [p1])

    r = c.delete(f"/api/v1/projects/{p1}/favorite", headers=actor_auth)
    check("取消收藏 = 204", r.status_code == 204)
    with engine.begin() as conn:
        conn.execute(sql("UPDATE projects SET status='taken_down' WHERE id=:p"), {"p": p2})
    r = c.get("/api/v1/me/favorites", headers=actor_auth)
    check("被下架的项目从我的收藏自动隐藏", all(x["id"] != p2 for x in r.json()["items"]))
    with engine.begin() as conn:
        conn.execute(sql("UPDATE projects SET status='published' WHERE id=:p"), {"p": p2})

    r = c.post(f"/api/v1/projects/{p1}/try", headers=actor_auth)
    check("加入想试 = 201", r.status_code == 201)
    r = c.get("/api/v1/me/try", headers=actor_auth)
    check("我的想试包含 P1", [x["id"] for x in r.json()["items"]] == [p1])
    r = c.get(f"/api/v1/projects/{p1}", headers=actor_auth)
    check("详情 viewer：is_tried=true / is_favorited=false", r.json()["viewer"]["is_tried"] is True
          and r.json()["viewer"]["is_favorited"] is False)
    r = c.delete(f"/api/v1/projects/{p1}/try", headers=actor_auth)
    check("移出想试 = 204", r.status_code == 204)

    r = c.post(f"/api/v1/projects/{p1}/reactions/creative", headers=actor_auth)
    check("点创意反馈 = 201", r.status_code == 201)
    r = c.post(f"/api/v1/projects/{p1}/reactions/nonsense", headers=actor_auth)
    check("非法反应类型 = 422", r.status_code == 422)
    r = c.get(f"/api/v1/projects/{p1}", headers=actor_auth)
    j = r.json()
    check("详情计数 reactions.creative=1 且 viewer 带 creative",
          j["counts"]["reactions"]["creative"] == 1 and j["viewer"]["reactions"] == ["creative"], str(j["counts"]))
    r = c.delete(f"/api/v1/projects/{p1}/reactions/creative", headers=actor_auth)
    check("取消反馈 = 204", r.status_code == 204)
    r = c.get(f"/api/v1/projects/{p1}")
    check("取消后计数归零", r.json()["counts"]["reactions"]["creative"] == 0)

    r = c.post(f"/api/v1/projects/{p2}/shares", json={"channel": "wechat", "status": "completed",
                                                      "anon_client_id": "smoke-anon-1"})
    check("游客记录分享 = 201（completed 进热度）", r.status_code == 201, r.text)

    print("== 5. 榜单（hot_score 红线：how_to×5 + 0.5^(age/72) 衰减）==")
    try:
        redis_client.delete("rankings:weekly_hot")  # 清缓存，保证用本次行为现算
    except Exception:
        pass
    r = c.get("/api/v1/rankings", params={"type": "weekly_hot", "limit": 100})
    j = r.json()
    ranked_ids = [x["project"]["id"] for x in j["items"]]
    check("本周热门包含 P1 和 P2", p1 in ranked_ids and p2 in ranked_ids, str(ranked_ids)[:200])
    check("P1（5 次想看×5）排在 P2（1 想看+1 收藏+1 分享）前",
          p1 in ranked_ids and p2 in ranked_ids and ranked_ids.index(p1) < ranked_ids.index(p2))
    check("rank 从 1 连续编号", [x["rank"] for x in j["items"]] == list(range(1, len(j["items"]) + 1)))
    with engine.connect() as conn:
        hs = conn.execute(sql("SELECT hot_score FROM projects WHERE id=:p"), {"p": p1}).scalar()
    check("hot_score 已回写 projects 表（≈25，衰减后略小）", hs is not None and 20 < hs <= 25.5, f"实际 {hs}")

    r = c.get("/api/v1/rankings", params={"type": "latest", "limit": 100})
    latest_ids = [x["project"]["id"] for x in r.json()["items"]]
    ours = [i for i in latest_ids if i in (p1, p2, p3)]
    check("最新榜：P1（最新发布）在我们的种子里排最前", ours and ours[0] == p1, str(ours))

    with engine.begin() as conn:
        conn.execute(sql("UPDATE projects SET featured_rank=2 WHERE id=:p"), {"p": p1})
        conn.execute(sql("UPDATE projects SET featured_rank=1 WHERE id=:p"), {"p": p2})
    r = c.get("/api/v1/rankings", params={"type": "today_pick"})
    pick_ids = [x["project"]["id"] for x in r.json()["items"]]
    check("今日精选按 featured_rank 排序（P2 在 P1 前）",
          p2 in pick_ids and p1 in pick_ids and pick_ids.index(p2) < pick_ids.index(p1), str(pick_ids))

    # ---- 清理本次测试数据（保持 dev 库干净）----
    with engine.begin() as conn:
        for t in ("notifications", "how_to_interests", "favorites", "try_items", "project_reactions",
                  "clue_subscriptions", "shares"):
            conn.execute(sql(f"DELETE FROM {t} WHERE project_id = ANY(CAST(:p AS uuid[]))"),
                         {"p": created_project_ids})
        conn.execute(sql("DELETE FROM similar_project_links WHERE source_project_id = ANY(CAST(:p AS uuid[]))"),
                     {"p": created_project_ids})
        conn.execute(sql("DELETE FROM projects WHERE id = ANY(CAST(:p AS uuid[]))"), {"p": created_project_ids})
        conn.execute(sql("DELETE FROM push_preferences WHERE user_id = ANY(CAST(:u AS uuid[]))"),
                     {"u": created_user_ids})
        conn.execute(sql("DELETE FROM users WHERE id = ANY(CAST(:u AS uuid[]))"), {"u": created_user_ids})
    try:
        redis_client.delete("rankings:weekly_hot")  # 含测试数据的榜单缓存不留给下个会话
    except Exception:
        pass

    print(f"\n结果：{passed} 通过 / {failed} 失败")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
