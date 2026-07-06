# ============================================================
# 这个文件是干什么的：V0 内容链路的端到端冒烟测试——对着真实运行的服务和数据库，
#   把"登录→上传→候选审核→通过发布→发现页可见"整条链跑一遍，包括各种该报错的场景。
# 它对应产品里的什么功能：验证 V0 全链路（鉴权/上传/审核/发现）行为正确。
# 如果它出错了，用户会看到什么现象：开发者会在上线前发现问题——这正是它存在的目的。
# 用法：先起服务（uvicorn app.main:app），再在 backend/ 下跑：
#   .venv/Scripts/python.exe tests/smoke_v0.py [BASE_URL，默认 http://127.0.0.1:8000]
# ============================================================
import base64
import sys
import time
import uuid as uuidlib

import httpx
from sqlalchemy import text as sql

from app.core.db import engine

BASE = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8000"
PNG_1PX = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
)

passed, failed = 0, 0
created_candidate_ids, created_project_ids = [], []


def check(name: str, cond: bool, extra=""):
    global passed, failed
    if cond:
        passed += 1
        print(f"  PASS  {name}")
    else:
        failed += 1
        print(f"  FAIL  {name}  {extra}")


def insert_candidate(conn, *, title, tools, description, score, cover=True) -> str:
    cid = str(uuidlib.uuid4())
    conn.execute(
        sql("""
        INSERT INTO candidate_contents
          (id, status, source_type, title, tagline, summary, description, category, language,
           domains, tools, tags_json, ai_implementation_hint, source_url, source_platform,
           original_author_name, cover_media_url, media_json, ai_curation_score)
        VALUES
          (:id, 'pending_review', 'ai_crawled', :title, '用 AI 一晚上做出可用工具', :summary, :description,
           'automation_tools', 'zh-CN', ARRAY['dev'], :tools, :tags, '1. 用 X 搭骨架 2. 接 Y 3. 部署',
           'https://example.com/post/1', 'x', '@maker', :cover, :media, :score)
        """),
        {
            "id": cid, "title": title,
            "summary": "这是一段超过二十个字的候选简介，描述这个 AI 用例做了什么、为什么值得一看。",
            "description": description, "tools": tools,
            "tags": '["AI编程", "效率工具"]',
            "cover": "https://example.com/cover.png" if cover else None,
            "media": '[{"url": "https://example.com/m1.png", "media_type": "image"}]',
            "score": score,
        },
    )
    created_candidate_ids.append(cid)
    return cid


def main():
    c = httpx.Client(base_url=BASE, timeout=15, trust_env=False)  # trust_env=False 绕过本机代理

    print("== 0. 健康检查 ==")
    check("GET /health = 200", c.get("/health").status_code == 200)

    print("== 1. auth 三件套 ==")
    phone = f"138{int(time.time()) % 100000000:08d}"
    r = c.post("/api/v1/auth/send-code", json={"identifier_type": "phone", "identifier": phone})
    check("send-code = 200", r.status_code == 200, r.text)
    r = c.post("/api/v1/auth/send-code", json={"identifier_type": "phone", "identifier": phone})
    check("send-code 60秒内重发 = 429 RATE_LIMITED", r.status_code == 429 and r.json()["code"] == "RATE_LIMITED")
    r = c.post("/api/v1/auth/send-code", json={"identifier_type": "phone", "identifier": "abc"})
    check("非法手机号 = 422", r.status_code == 422)

    r = c.post("/api/v1/auth/login", json={"identifier_type": "phone", "identifier": phone, "code": "000000"})
    check("错误验证码 = 422", r.status_code == 422)
    r = c.post("/api/v1/auth/login", json={"identifier_type": "phone", "identifier": phone, "code": "888888"})
    check("dev 万能码登录 = 200", r.status_code == 200, r.text)
    body = r.json()
    check("登录返回双令牌 + is_new_user=true", bool(body.get("access_token")) and body.get("is_new_user") is True)
    admin_token, admin_uid = body["access_token"], body["user"]["id"]

    r = c.post("/api/v1/auth/refresh", json={"refresh_token": body["refresh_token"]})
    check("refresh = 200 且换发新令牌", r.status_code == 200 and r.json()["access_token"] != admin_token)
    r = c.post("/api/v1/auth/refresh", json={"refresh_token": admin_token})
    check("用 access 当 refresh = 401", r.status_code == 401)

    print("== 2. 鉴权边界 ==")
    check("无 token 调 /me = 401 AUTH_REQUIRED",
          c.get("/api/v1/me").status_code == 401)
    r = c.get("/api/v1/admin/candidates", headers={"Authorization": f"Bearer {admin_token}"})
    check("普通用户调后台 = 403 FORBIDDEN", r.status_code == 403 and r.json()["code"] == "FORBIDDEN")

    with engine.begin() as conn:
        conn.execute(sql("UPDATE users SET is_admin = true WHERE id = :id"), {"id": admin_uid})
    auth = {"Authorization": f"Bearer {admin_token}"}
    check("设为管理员后调后台 = 200", c.get("/api/v1/admin/candidates", headers=auth).status_code == 200)

    print("== 3. 媒体上传 ==")
    r = c.post("/api/v1/media", headers=auth, files={"file": ("a.png", PNG_1PX, "image/png")})
    check("上传 png = 201", r.status_code == 201, r.text)
    media_url = r.json()["url"]
    check("上传文件可访问", c.get(media_url).status_code == 200)
    r = c.post("/api/v1/media", headers=auth, files={"file": ("a.gif", b"GIF89a", "image/gif")})
    check("不支持的类型 = 422", r.status_code == 422)
    r = c.post("/api/v1/media", files={"file": ("a.png", PNG_1PX, "image/png")})
    check("游客上传 = 401", r.status_code == 401)

    print("== 4. 候选审核流（approve §5.3 最关键）==")
    marker = f"冒烟{int(time.time()) % 100000}"
    with engine.begin() as conn:
        good = insert_candidate(conn, title=f"{marker} 高分候选", tools=["Claude Code", "FastAPI"],
                                description="完整复现步骤：先用脚手架生成骨架，再接 API，最后一键部署上线。", score=85)
        good2 = insert_candidate(conn, title=f"{marker} 中分候选", tools=["Midjourney"],
                                 description="复现思路：准备提示词模板，批量出图后人工筛选精修。", score=70)
        bad = insert_candidate(conn, title=f"{marker} 纯单图无方法", tools=[], description=None, score=90)

    r = c.get("/api/v1/admin/candidates", headers=auth, params={"status": "pending_review", "min_score": 80, "q": marker})
    ids = [x["id"] for x in r.json()["items"]]
    check("列表筛选（status+min_score+q）只命中高分候选", ids == [bad, good] or set(ids) == {good, bad}, str(ids))

    r = c.get(f"/api/v1/admin/candidates/{good}", headers=auth)
    check("候选详情 = 200（含可空字段归一化）", r.status_code == 200 and r.json()["target_users"] == [], r.text[:200])

    r = c.patch(f"/api/v1/admin/candidates/{good}", headers=auth, json={"tagline": "一晚上搓出能用的工具"})
    check("编辑候选 = 200 且状态→edited", r.status_code == 200 and r.json()["status"] == "edited", r.text)

    r = c.post(f"/api/v1/admin/candidates/{bad}/approve", headers=auth)
    check("纯单图无方法 approve = 409 PUBLISH_GATE_FAILED（红线）",
          r.status_code == 409 and r.json()["code"] == "PUBLISH_GATE_FAILED", r.text)

    r = c.post(f"/api/v1/admin/candidates/{good}/approve", headers=auth)
    check("合格候选 approve = 201 返回 project_id", r.status_code == 201, r.text)
    project_id = r.json()["project_id"]
    created_project_ids.append(project_id)
    r2 = c.post(f"/api/v1/admin/candidates/{good2}/approve", headers=auth)
    check("第二个候选 approve = 201", r2.status_code == 201, r2.text)
    created_project_ids.append(r2.json()["project_id"])

    r = c.post(f"/api/v1/admin/candidates/{good}/approve", headers=auth)
    check("重复 approve = 409 CANDIDATE_INVALID_STATE",
          r.status_code == 409 and r.json()["code"] == "CANDIDATE_INVALID_STATE")
    r = c.post(f"/api/v1/admin/candidates/{bad}/park", headers=auth)
    check("park = 200（→parked）", r.status_code == 200)
    r = c.post(f"/api/v1/admin/candidates/{bad}/discard", headers=auth, json={"reason": "无方法说明"})
    check("discard = 200（→discarded）", r.status_code == 200)

    print("== 5. 发现页列表/详情（游客视角）==")
    r = c.get("/api/v1/projects", params={"q": marker})
    items = r.json()["items"]
    check("发现页能搜到刚发布的 2 个项目", r.status_code == 200 and len(items) == 2, r.text[:200])
    r = c.get("/api/v1/projects", params={"q": marker, "page_size": 1})
    j = r.json()
    check("游标分页：第1页 1 条且 has_more", len(j["items"]) == 1 and j["has_more"] and j["next_cursor"])
    r = c.get("/api/v1/projects", params={"q": marker, "page_size": 1, "cursor": j["next_cursor"]})
    j2 = r.json()
    check("游标翻页：第2页 1 条且无更多", len(j2["items"]) == 1 and not j2["has_more"]
          and j2["items"][0]["id"] != j["items"][0]["id"])
    r = c.get("/api/v1/projects", params={"q": marker, "cursor": "!!!bad!!!"})
    check("坏 cursor = 422", r.status_code == 422)
    r = c.get("/api/v1/projects", params={"domain": "dev", "q": marker})
    check("domain=dev 筛选命中", len(r.json()["items"]) >= 1)
    r = c.get("/api/v1/projects", params={"domain": "design", "q": marker})
    check("domain=design 筛选为空", len(r.json()["items"]) == 0)

    r = c.get(f"/api/v1/projects/{project_id}")
    d = r.json()
    check("详情 = 200", r.status_code == 200, r.text[:200])
    check("ai_badge 按分数映射 high_potential（85≥80）", d.get("ai_badge") == "high_potential")
    check("媒体已从 media_json 落表（1 条）", len(d.get("media", [])) == 1)
    check("标签已拆解（2 个）", sorted(d.get("tags", [])) == ["AI编程", "效率工具"], str(d.get("tags")))
    check("AI 实现思路已带上", bool(d.get("ai_implementation_hint")))
    check("游客 viewer 状态全 false", d["viewer"]["is_favorited"] is False)
    check("登录后详情 = 200（viewer 通路）", c.get(f"/api/v1/projects/{project_id}", headers=auth).status_code == 200)
    check("不存在的项目 = 404", c.get(f"/api/v1/projects/{uuidlib.uuid4()}").status_code == 404)

    print("== 6. 操作留痕 ==")
    with engine.connect() as conn:
        n = conn.execute(sql(
            "SELECT count(*) FROM admin_actions WHERE admin_user_id = :a"), {"a": admin_uid}).scalar()
    # 本轮应留痕：edit + approve×2 + park + discard = 5（被 409 拒掉的 approve 不留痕，正确）
    check("admin_actions 已记录全部后台动作（恰好 5 条）", n == 5, f"实际 {n}")

    # ---- 清理本次测试数据（保持 dev 库干净）----
    with engine.begin() as conn:
        for pid in created_project_ids:
            conn.execute(sql("DELETE FROM project_tag_relations WHERE project_id = :p"), {"p": pid})
            conn.execute(sql("DELETE FROM project_media WHERE project_id = :p"), {"p": pid})
        conn.execute(sql("DELETE FROM project_tags WHERE name IN ('AI编程','效率工具')"))
        for cid in created_candidate_ids:
            conn.execute(sql("DELETE FROM candidate_contents WHERE id = :c"), {"c": cid})
        for pid in created_project_ids:
            conn.execute(sql("DELETE FROM projects WHERE id = :p"), {"p": pid})

    print(f"\n结果：{passed} 通过 / {failed} 失败")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
