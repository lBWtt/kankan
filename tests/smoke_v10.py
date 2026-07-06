# ============================================================
# 这个文件是干什么的：新版项目详情和 action 主链路的端到端冒烟测试。
# 它对应产品里的什么功能：新版发布页、详情页按钮、游客行为流水和热度榜计算。
# 如果它出错了，开发者会在上线前看到新版前端需要的后端契约没有接稳。
# 用法：先起服务并 alembic upgrade head，再在 backend/ 下跑：
#   .venv/Scripts/python.exe -X utf8 tests/smoke_v10.py [BASE_URL，默认 http://127.0.0.1:8000]
# ============================================================
import sys
import time

import httpx
from sqlalchemy import text as sql

from app.core.db import SessionLocal, engine
from app.services.rankings import compute_weekly_hot

BASE = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8000"
MARK = f"v2action{int(time.time()) % 100000}"

passed, failed = 0, 0
project_ids, user_ids = [], []


def check(name: str, cond: bool, extra=""):
    global passed, failed
    if cond:
        passed += 1
        print(f"  PASS  {name}")
    else:
        failed += 1
        print(f"  FAIL  {name}  {extra}")


def main():
    c = httpx.Client(base_url=BASE, timeout=15, trust_env=False)

    print("== 1. 登录 + 新版发布 ==")
    check("GET /health = 200", c.get("/health").status_code == 200)
    phone = f"136{int(time.time()) % 100000000:08d}"
    r = c.post("/api/v1/auth/login", json={"identifier_type": "phone", "identifier": phone, "code": "888888"})
    check("dev 登录 = 200", r.status_code == 200, r.text[:200])
    token = r.json()["access_token"]
    user_ids.append(r.json()["user"]["id"])
    auth = {"Authorization": f"Bearer {token}"}

    intro = (
        f"{MARK} 用 Claude 把重复整理资料的步骤变成一个可复用工作流：先收集素材，再生成结构化摘要，"
        "最后人工确认并发布。"
    )
    payload = {
        "intro": intro,
        "vertical": "Vibe Coding",
        "source_kind": "original",
        "media_ids": [],
        "tags": [MARK],
        "actions": [
            {
                "type": "take",
                "sub": "text",
                "label": "复制工作流",
                "content": "把输入资料整理成标题、要点、下一步行动。",
                "sortOrder": 0,
            },
            {
                "type": "go",
                "sub": "github",
                "label": "看示例仓库",
                "url": "https://github.com/example/ccpj-demo",
                "sortOrder": 1,
            },
            {
                "type": "how",
                "sub": "url",
                "label": "看完整做法",
                "url": "https://example.com/how-to-build",
                "sortOrder": 2,
            },
        ],
    }
    r = c.post("/api/v1/projects", headers=auth, json=payload)
    check("新版无媒体但有 actions 发布 = 201", r.status_code == 201, r.text[:300])
    d = r.json()
    pid = d["id"]
    project_ids.append(pid)
    check("详情回传 intro/vertical/actions", d["intro"] == intro and d["vertical"] == "Vibe Coding"
          and len(d["actions"]) == 3, str(d))
    check("vertical 映射到 category/domains", d["category"] == "creator_tools" and d["domains"] == ["dev"],
          str({"category": d.get("category"), "domains": d.get("domains")}))
    check("初始 takeaway_count/counts.takeaways = 0", d["takeaway_count"] == 0 and d["counts"]["takeaways"] == 0)

    print("== 2. 发布准入和 URL 校验 ==")
    r = c.post("/api/v1/projects", headers=auth, json={
        "intro": "短介绍",
        "vertical": "设计",
        "media_ids": [],
        "actions": [],
    })
    check("无工具/无 action/短 intro = 409 PUBLISH_GATE_FAILED",
          r.status_code == 409 and r.json()["code"] == "PUBLISH_GATE_FAILED", r.text[:200])

    r = c.post("/api/v1/projects", headers=auth, json={
        "intro": f"{MARK} 这是一个长度足够的说明，但 action 链接不能是脚本协议。",
        "vertical": "效率工具",
        "actions": [{"type": "go", "sub": "url", "label": "坏链接", "url": "javascript:alert(1)"}],
    })
    check("action.url 拦截非 http/https = 422",
          r.status_code == 422 and r.json()["code"] == "VALIDATION_FAILED", r.text[:200])

    print("== 3. 游客 action 事件和计数 ==")
    take_id = next(x["id"] for x in d["actions"] if x["type"] == "take")
    go_id = next(x["id"] for x in d["actions"] if x["type"] == "go")

    r = c.post(f"/api/v1/projects/{pid}/actions/{go_id}/events", json={"eventType": "click"})
    check("游客 action 事件缺 anonClientId = 422 ANON_ID_REQUIRED",
          r.status_code == 422 and r.json()["code"] == "ANON_ID_REQUIRED", r.text[:200])

    r = c.post(f"/api/v1/projects/{pid}/actions/{go_id}/events",
               json={"eventType": "click", "anonClientId": f"{MARK}-anon"})
    check("游客 go click = 201 且不增加拿走数", r.status_code == 201 and r.json()["takeaway_count"] == 0,
          r.text[:200])
    r = c.post(f"/api/v1/projects/{pid}/actions/{take_id}/events",
               json={"eventType": "success", "anonClientId": f"{MARK}-anon"})
    check("游客 take success = 201 且 takeaway_count +1",
          r.status_code == 201 and r.json()["takeaway_count"] == 1, r.text[:200])

    r = c.post(f"/api/v1/projects/{pid}/how-to-interest", json={"anon_client_id": f"{MARK}-how"})
    check("how-to-interest 游客仍可写入", r.status_code == 201 and r.json()["how_to_interest_count"] == 1,
          r.text[:200])

    d2 = c.get(f"/api/v1/projects/{pid}").json()
    check("详情计数包含 action_clicks/takeaways",
          d2["counts"]["action_clicks"] == 1 and d2["counts"]["takeaways"] == 1
          and d2["takeaway_count"] == 1, str(d2["counts"]))

    print("== 4. hot_score 新行为权重 ==")
    with SessionLocal() as db:
        scores = dict(compute_weekly_hot(db, limit=None))
        score = float(scores.get(pid, 0))
    check("hot_score 包含 go click(3) + take success(6) + how_to_interest(5)",
          score > 13.0, f"score={score}")

    with engine.begin() as conn:
        for pid_ in project_ids:
            conn.execute(sql("DELETE FROM project_action_events WHERE project_id = CAST(:p AS uuid)"), {"p": pid_})
            conn.execute(sql("DELETE FROM project_actions WHERE project_id = CAST(:p AS uuid)"), {"p": pid_})
            conn.execute(sql("DELETE FROM how_to_interests WHERE project_id = CAST(:p AS uuid)"), {"p": pid_})
            conn.execute(sql("DELETE FROM project_tag_relations WHERE project_id = CAST(:p AS uuid)"), {"p": pid_})
        conn.execute(sql("DELETE FROM project_tags WHERE name = :name"), {"name": MARK})
        for pid_ in project_ids:
            conn.execute(sql("DELETE FROM projects WHERE id = CAST(:p AS uuid)"), {"p": pid_})
        for uid in user_ids:
            conn.execute(sql("DELETE FROM push_preferences WHERE user_id = CAST(:u AS uuid)"), {"u": uid})
            conn.execute(sql("DELETE FROM users WHERE id = CAST(:u AS uuid)"), {"u": uid})

    print(f"\n结果：{passed} 通过 / {failed} 失败")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
