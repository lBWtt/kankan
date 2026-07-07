# ============================================================
# 这个文件是干什么的：上线级护栏的冒烟测试——四项加固：①万能码只在 dev+默认密钥下启用；
#   ②埋点限频静默丢弃；③幂等写并发不再 500（收藏/反馈/想看怎么做/推送偏好/标签并发 race）；
#   ④候选 ai_collected 不许直接 approve。
# 它对应产品里的什么功能：账号安全、反刷榜、高并发下按钮不报错、AI 生料不漏发。
# 如果它出错了，用户会看到什么现象：开发者上线前就拦住——这正是它存在的目的。
# 用法：先起服务（uvicorn app.main:app），再在 backend/ 下（设 PYTHONPATH=.）跑：
#   .venv/Scripts/python.exe -X utf8 tests/smoke_v7.py [BASE_URL，默认 http://127.0.0.1:8000]
# ============================================================
import sys
import time
import uuid as uuidlib
from concurrent.futures import ThreadPoolExecutor

import httpx
from sqlalchemy import text as sql

from app.core.config import Settings, dev_login_enabled
from app.core.db import SessionLocal, engine
from app.core.redis import redis_client
from app.services.publishing import _get_or_create_tag

BASE = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8000"
MARK = f"v7_{int(time.time()) % 100000}"

passed, failed = 0, 0


def check(name: str, cond: bool, extra=""):
    global passed, failed
    if cond:
        passed += 1
        print(f"  PASS  {name}")
    else:
        failed += 1
        print(f"  FAIL  {name}  {extra}")


def new_client():
    return httpx.Client(base_url=BASE, timeout=20, trust_env=False)  # trust_env=False 绕过本机代理


def burst(n, fn):
    """并发跑 n 次 fn()，按提交顺序返回结果列表。"""
    with ThreadPoolExecutor(max_workers=n) as ex:
        return [f.result() for f in [ex.submit(fn) for _ in range(n)]]


def login(c, prefix="138"):
    phone = f"{prefix}{int(time.time() * 1000) % 100000000:08d}"
    r = c.post("/api/v1/auth/login", json={"identifier_type": "phone", "identifier": phone, "code": "888888"})
    return r.json()["user"]["id"], {"Authorization": f"Bearer {r.json()['access_token']}"}


def seed_published_project(conn) -> str:
    pid = str(uuidlib.uuid4())
    conn.execute(sql("""
        INSERT INTO projects (id, title, tagline, summary, category, language, source_type,
                              is_original, source_url, status, hot_score, allow_how_to_interest)
        VALUES (CAST(:id AS uuid), :t, '占位亮点够长了', :s, 'work_efficiency', 'zh-CN',
                'ai_crawled', false, :u, 'published', 0, true)
    """), {"id": pid, "t": f"{MARK} 互动测试项目", "u": f"https://example.com/{MARK}/proj",
           "s": "占位简介——超过二十个字以满足数据库与契约的最短长度要求，用于并发互动测试。"})
    return pid


def seed_full_candidate(conn, status: str) -> str:
    """字段齐到能过发布准入的候选——这样 approve 若被拦，证明拦的是状态机而非发布准入。"""
    cid = str(uuidlib.uuid4())
    conn.execute(sql("""
        INSERT INTO candidate_contents
          (id, status, source_type, title, tagline, summary, description, category, language,
           domains, tools, tags_json, source_url, source_platform, original_author_name,
           cover_media_url, media_json, ai_curation_score)
        VALUES
          (CAST(:id AS uuid), CAST(:st AS candidate_status), 'ai_crawled', :title, '一句话亮点够长了',
           :summary, '完整复现步骤：先搭骨架，再接 API，最后部署上线，过程清晰可照做。',
           'work_efficiency', 'zh-CN', ARRAY['office'], ARRAY['Claude'], :tags,
           :url, 'x', '@maker', :cover, :media, 85)
    """), {"id": cid, "st": status, "title": f"{MARK} 候选-{status}",
           "summary": "这是一段超过二十个字的候选简介，描述这个 AI 用例做了什么、为什么值得一看。",
           "tags": '{"items": ["效率工具"]}', "url": f"https://example.com/{MARK}/cand-{status}",
           "cover": "https://example.com/cover.png",
           "media": '{"items": [{"url": "https://example.com/m1.png", "media_type": "image"}]}'})
    return cid


def main():
    created_projects, created_candidates = [], []

    print("== 1. app_env 加固：万能码 888888 的启用门槛 ==")
    check("dev + 默认 JWT 密钥 → 万能码启用", dev_login_enabled(Settings()) is True)
    check("dev + 换过 JWT 密钥 → 万能码失效（忘配 prod 也安全）",
          dev_login_enabled(Settings(jwt_secret="a-real-secret")) is False)
    check("prod 环境 → 万能码失效", dev_login_enabled(Settings(app_env="prod")) is False)

    c = new_client()
    check("GET /health = 200", c.get("/health").status_code == 200)
    admin_uid, admin_auth = login(c, "137")
    with engine.begin() as conn:
        conn.execute(sql("UPDATE users SET is_admin = true WHERE id = CAST(:id AS uuid)"), {"id": admin_uid})

    print("== 2. 候选状态机：ai_collected 不许直接 approve ==")
    with engine.begin() as conn:
        collected = seed_full_candidate(conn, "ai_collected")
        ready = seed_full_candidate(conn, "pending_review")
        collected2 = seed_full_candidate(conn, "ai_collected")
        created_candidates += [collected, ready, collected2]

    r = c.post(f"/api/v1/admin/candidates/{collected}/approve", headers=admin_auth)
    check("字段齐但 ai_collected → approve = 409 CANDIDATE_INVALID_STATE（拦的是状态机非准入）",
          r.status_code == 409 and r.json()["code"] == "CANDIDATE_INVALID_STATE", r.text[:200])
    r = c.post(f"/api/v1/admin/candidates/{collected2}/park", headers=admin_auth)
    check("ai_collected 仍可 park（没误伤合法流转）", r.status_code == 200, r.text[:200])
    r = c.post(f"/api/v1/admin/candidates/{ready}/approve", headers=admin_auth)
    check("同样字段 pending_review → approve = 201（对照组：状态对就能发）", r.status_code == 201, r.text[:200])
    if r.status_code == 201:
        created_projects.append(r.json()["project_id"])

    print("== 3. 幂等写并发安全：8 路并发不报 500、只落 1 行 ==")
    with engine.begin() as conn:
        pid = seed_published_project(conn)
        created_projects.append(pid)
    user_uid, user_auth = login(c, "136")

    def do_fav():
        with new_client() as cc:
            return cc.post(f"/api/v1/projects/{pid}/favorite", headers=user_auth).status_code
    codes = burst(8, do_fav)
    with engine.connect() as conn:
        n = conn.execute(sql("SELECT count(*) FROM favorites WHERE project_id = CAST(:p AS uuid)"),
                         {"p": pid}).scalar()
    check("并发收藏：无 500 且恰好 1 行", 500 not in codes and n == 1, f"codes={codes} rows={n}")

    def do_react():
        with new_client() as cc:
            return cc.post(f"/api/v1/projects/{pid}/reactions/creative", headers=user_auth).status_code
    codes = burst(8, do_react)
    with engine.connect() as conn:
        n = conn.execute(sql("SELECT count(*) FROM project_reactions WHERE project_id = CAST(:p AS uuid)"),
                         {"p": pid}).scalar()
    check("并发创意反馈：无 500 且恰好 1 行", 500 not in codes and n == 1, f"codes={codes} rows={n}")

    anon = f"anon-{MARK}"

    def do_hti():
        with new_client() as cc:
            return cc.post(f"/api/v1/projects/{pid}/how-to-interest", json={"anon_client_id": anon}).status_code
    codes = burst(8, do_hti)
    with engine.connect() as conn:
        n = conn.execute(sql("SELECT count(*) FROM how_to_interests WHERE project_id = CAST(:p AS uuid)"),
                         {"p": pid}).scalar()
    check("并发想看怎么做（同游客）：无 500 且恰好 1 行（主信号不重复计数）",
          500 not in codes and n == 1, f"codes={codes} rows={n}")

    # 推送偏好：新用户首屏并发 GET，首次建行的 race
    pref_uid, pref_auth = login(c, "135")

    def do_pref():
        with new_client() as cc:
            return cc.get("/api/v1/me/push-preferences", headers=pref_auth).status_code
    codes = burst(8, do_pref)
    with engine.connect() as conn:
        n = conn.execute(sql("SELECT count(*) FROM push_preferences WHERE user_id = CAST(:u AS uuid)"),
                         {"u": pref_uid}).scalar()
    check("并发首取推送偏好：无 500 且恰好 1 行", 500 not in codes and n == 1, f"codes={codes} rows={n}")

    # 标签字典 get-or-create 的 SAVEPOINT 并发（直接打服务层，最贴近双项目同标签发布）
    tag_name = f"{MARK}并发标签"

    def do_tag():
        db = SessionLocal()
        try:
            t = _get_or_create_tag(db, tag_name)
            db.commit()
            return str(t.id)
        except Exception as e:  # noqa: BLE001 —— 测试要捕获任何异常证明不抛
            return f"ERR:{e}"
        finally:
            db.close()
    results = burst(8, do_tag)
    with engine.connect() as conn:
        n = conn.execute(sql("SELECT count(*) FROM project_tags WHERE name = :nm"), {"nm": tag_name}).scalar()
    check("并发建同名标签：无异常、恰好 1 行、所有线程拿到同一 id",
          all(not r.startswith("ERR") for r in results) and n == 1 and len(set(results)) == 1,
          f"results={results} rows={n}")

    print("== 4. 埋点限频：超额静默丢弃，不报错 ==")
    redis_client.delete(f"events:rl:a:{anon}")  # 清窗口，避免重跑时残留计数

    def send_events(count):
        body = {"events": [{"event_name": "v7_probe"} for _ in range(count)],
                "client_info": {"anon_client_id": anon}}
        return c.post("/api/v1/events", json=body)

    r1 = send_events(50)
    check("首批 50 条全收（≤100）", r1.status_code == 201 and r1.json()["accepted"] == 50, r1.text)
    r2 = send_events(50)  # 累计 100，仍 ≤ 阈值
    check("次批 50 条全收（累计 100）", r2.status_code == 201 and r2.json()["accepted"] == 50, r2.text)
    r3 = send_events(50)  # 累计 150 > 100
    check("超额批次静默丢弃：201 且 accepted=0（不报错）",
          r3.status_code == 201 and r3.json()["accepted"] == 0, r3.text)
    with engine.connect() as conn:
        n = conn.execute(sql("SELECT count(*) FROM analytics_events WHERE event_name = 'v7_probe'")).scalar()
    check("入库条数被限在阈值内（=100，未把超额刷进库）", n == 100, f"实际 {n}")

    # 关键：喂 hot_score 的 card_impression（带 project_id）超频后也必须零入库——
    # 否则刷曝光就能刷榜。anon 计数此刻已 >100，这批必丢。
    r4 = c.post("/api/v1/events", json={
        "events": [{"event_name": "card_impression", "project_id": pid} for _ in range(10)],
        "client_info": {"anon_client_id": anon}})
    with engine.connect() as conn:
        impressions = conn.execute(sql(
            "SELECT count(*) FROM analytics_events WHERE project_id = CAST(:p AS uuid) "
            "AND event_name = 'card_impression'"), {"p": pid}).scalar()
    check("超额 card_impression 被丢且零入库（不喂 hot_score，杜绝刷曝光刷榜）",
          r4.status_code == 201 and r4.json()["accepted"] == 0 and impressions == 0,
          f"accepted={r4.json().get('accepted')} 入库={impressions}")

    # ---- 清理本轮测试数据 ----
    redis_client.delete(f"events:rl:a:{anon}")
    with engine.begin() as conn:
        conn.execute(sql("DELETE FROM analytics_events WHERE event_name = 'v7_probe'"))
        conn.execute(sql("DELETE FROM analytics_events WHERE project_id = CAST(:p AS uuid)"), {"p": pid})
        conn.execute(sql("DELETE FROM favorites WHERE project_id = CAST(:p AS uuid)"), {"p": pid})
        conn.execute(sql("DELETE FROM project_reactions WHERE project_id = CAST(:p AS uuid)"), {"p": pid})
        conn.execute(sql("DELETE FROM how_to_interests WHERE project_id = CAST(:p AS uuid)"), {"p": pid})
        conn.execute(sql("DELETE FROM project_tags WHERE name = :nm"), {"nm": tag_name})
        for cid in created_candidates:
            conn.execute(sql("DELETE FROM candidate_contents WHERE id = CAST(:c AS uuid)"), {"c": cid})
        for ppid in created_projects:
            conn.execute(sql("DELETE FROM project_tag_relations WHERE project_id = CAST(:p AS uuid)"), {"p": ppid})
            conn.execute(sql("DELETE FROM project_media WHERE project_id = CAST(:p AS uuid)"), {"p": ppid})
        conn.execute(sql("DELETE FROM project_tags WHERE name = '效率工具'"))
        for ppid in created_projects:
            conn.execute(sql("DELETE FROM projects WHERE id = CAST(:p AS uuid)"), {"p": ppid})
        conn.execute(sql("DELETE FROM admin_actions WHERE admin_user_id = CAST(:u AS uuid)"), {"u": admin_uid})
        for uid in (admin_uid, user_uid, pref_uid):
            conn.execute(sql("DELETE FROM push_preferences WHERE user_id = CAST(:u AS uuid)"), {"u": uid})
            conn.execute(sql("DELETE FROM users WHERE id = CAST(:u AS uuid)"), {"u": uid})

    print(f"\n结果：{passed} 通过 / {failed} 失败")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
