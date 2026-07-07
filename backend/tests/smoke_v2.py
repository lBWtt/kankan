# ============================================================
# 这个文件是干什么的：用户发布链路 + 我的资料系列的端到端冒烟测试——对着真实运行的服务，
#   把"上传媒体→发布原创/发现分享→我做了类似的→编辑→软删→我的发布列表→资料/兴趣/推送偏好"
#   整条链跑一遍，包括准入 409、越权 403、媒体校验 422 等该报错的场景。
# 它对应产品里的什么功能：发布 Tab、"我的"页、设置页。
# 如果它出错了，用户会看到什么现象：开发者会在上线前发现问题——这正是它存在的目的。
# 用法：先起服务（uvicorn app.main:app），再在 backend/ 下跑：
#   .venv/Scripts/python.exe tests/smoke_v2.py [BASE_URL，默认 http://127.0.0.1:8000]
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


def upload(c, auth) -> str:
    r = c.post("/api/v1/media", headers=auth, files={"file": ("a.png", PNG_1PX, "image/png")})
    assert r.status_code == 201, r.text
    return r.json()["id"]


def project_payload(marker, media_ids, **overrides):
    base = {
        "title": f"{marker} 原创项目",
        "tagline": "用 AI 一晚上做出可用工具",
        "summary": "这是一段超过二十个字的项目简介，描述这个 AI 用例做了什么、为什么值得一看。",
        "description": "完整复现步骤：先用脚手架生成骨架，再接 API，最后一键部署上线。",
        "category": "automation_tools",
        "domains": ["dev"],
        "tools": ["Claude Code"],
        "media_ids": media_ids,
        "is_original": True,
        "tags": ["AI编程冒烟", "效率工具冒烟"],
    }
    base.update(overrides)
    return base


def main():
    c = httpx.Client(base_url=BASE, timeout=15, trust_env=False)  # trust_env=False 绕过本机代理
    ts = int(time.time())
    marker = f"V2冒烟{ts % 100000}"

    print("== 0. 准备：两个用户 ==")
    author_auth, author_uid = login(c, f"135{ts % 100000000:08d}")
    other_auth, other_uid = login(c, f"134{(ts + 3) % 100000000:08d}")

    print("== 1. 发布项目（POST /projects）==")
    r = c.post("/api/v1/projects", json=project_payload(marker, []))
    check("游客发布 = 401", r.status_code == 401)
    r = c.post("/api/v1/projects", headers=author_auth, json=project_payload(marker, []))
    check("media_ids 为空 = 422（媒体至少一个）", r.status_code == 422)

    m1, m2 = upload(c, author_auth), upload(c, author_auth)
    r = c.post("/api/v1/projects", headers=author_auth,
               json=project_payload(marker, [m1], tools=[], description=None))
    check("纯单图无方法 = 409 PUBLISH_GATE_FAILED（红线）",
          r.status_code == 409 and r.json()["code"] == "PUBLISH_GATE_FAILED", r.text)

    r = c.post("/api/v1/projects", headers=author_auth, json=project_payload(marker, [m1, m2]))
    check("原创发布 = 201", r.status_code == 201, r.text[:300])
    pa = r.json()
    check("默认直接发布（status=published）+ source_type=user_original",
          pa["status"] == "published" and pa["source_type"] == "user_original")
    check("作者信息带上、ai_badge=none", pa["author"]["id"] == author_uid and pa["ai_badge"] == "none")
    check("媒体按顺序挂载（2 张）+ 第一张是封面",
          len(pa["media"]) == 2 and pa["cover_media_url"] == pa["media"][0]["url"], str(pa["media"]))
    check("标签落表（2 个）", sorted(pa["tags"]) == ["AI编程冒烟", "效率工具冒烟"], str(pa["tags"]))
    pa_id = pa["id"]

    r = c.post("/api/v1/projects", headers=author_auth, json=project_payload(marker, [m1]))
    check("复用已挂载的媒体 = 422（媒体已被其他项目使用）", r.status_code == 422, r.text)

    r = c.post("/api/v1/projects", headers=author_auth,
               json=project_payload(marker, [upload(c, author_auth)], is_original=False))
    check("发现分享缺来源链接 = 422（schema 校验）", r.status_code == 422)
    r = c.post("/api/v1/projects", headers=author_auth,
               json=project_payload(marker, [upload(c, author_auth)], title=f"{marker} 发现分享",
                                    is_original=False, source_url="https://example.com/post/9",
                                    original_author_name="@maker"))
    check("发现分享发布 = 201 且 source_type=user_discovery",
          r.status_code == 201 and r.json()["source_type"] == "user_discovery", r.text[:200])
    pb_id = r.json()["id"]

    print("== 2. 我做了类似的（§5.2）==")
    r = c.post("/api/v1/projects", headers=other_auth,
               json=project_payload(marker, [upload(c, other_auth)], title=f"{marker} 类似作品",
                                    related_original_project_id=pa_id, is_original=False))
    check("带 related 但 is_original=false = 422（强制原创）", r.status_code == 422)
    r = c.post("/api/v1/projects", headers=other_auth,
               json=project_payload(marker, [upload(c, other_auth)], title=f"{marker} 类似作品",
                                    related_original_project_id=pa_id))
    check("「我做了类似的」发布 = 201", r.status_code == 201, r.text[:200])
    pc_id = r.json()["id"]
    r = c.get(f"/api/v1/projects/{pa_id}/similar")
    check("原项目类似作品区展示新作品", [x["id"] for x in r.json()["items"]] == [pc_id], r.text[:200])
    r = c.get("/api/v1/notifications", headers=author_auth, params={"unread_only": True})
    notifs = [n for n in r.json()["items"] if n["type"] == "similar_project"]
    check("原作者收到 similar_project 通知（落点=新作品）",
          len(notifs) == 1 and notifs[0]["project_id"] == pc_id, str(notifs))

    print("== 3. 编辑 / 软删（归属与状态红线）==")
    r = c.patch(f"/api/v1/projects/{pa_id}", headers=other_auth, json={"title": "改别人的"})
    check("改别人的项目 = 403 FORBIDDEN", r.status_code == 403 and r.json()["code"] == "FORBIDDEN")
    r = c.patch(f"/api/v1/projects/{pa_id}", headers=author_auth, json={"tagline": "改后的亮点不少于五字"})
    check("轻编辑直接生效 = 200", r.status_code == 200 and r.json()["tagline"] == "改后的亮点不少于五字", r.text[:200])
    r = c.patch(f"/api/v1/projects/{pa_id}", headers=author_auth, json={"tools": [], "description": None})
    check("把已发布项目改成纯单图无方法 = 409（准入复检）",
          r.status_code == 409 and r.json()["code"] == "PUBLISH_GATE_FAILED", r.text)
    m3 = upload(c, author_auth)
    r = c.patch(f"/api/v1/projects/{pa_id}", headers=author_auth, json={"media_ids": [m3], "tags": ["新标签冒烟"]})
    j = r.json()
    check("换媒体+换标签 = 200（封面跟随新首图、旧标签清掉）",
          r.status_code == 200 and len(j["media"]) == 1 and j["media"][0]["id"] == m3
          and j["cover_media_url"] == j["media"][0]["url"] and j["tags"] == ["新标签冒烟"], r.text[:300])

    r = c.delete(f"/api/v1/projects/{pb_id}", headers=other_auth)
    check("删别人的项目 = 403", r.status_code == 403)
    r = c.delete(f"/api/v1/projects/{pb_id}", headers=author_auth)
    check("软删自己的项目 = 204", r.status_code == 204)
    check("软删后详情 404（对外不可见）", c.get(f"/api/v1/projects/{pb_id}").status_code == 404)
    with engine.connect() as conn:
        st = conn.execute(sql("SELECT status, deleted_at FROM projects WHERE id=:p"), {"p": pb_id}).one()
    check("软删=deleted+deleted_at（记录还在，红线：不物理删）", st[0] == "deleted" and st[1] is not None, str(st))
    check("重复删 = 404", c.delete(f"/api/v1/projects/{pb_id}", headers=author_auth).status_code == 404)

    print("== 4. 我的发布列表 ==")
    r = c.get("/api/v1/me/projects", headers=author_auth)
    ids = [x["id"] for x in r.json()["items"]]
    check("我的发布：剩 1 个（软删的不出现）", ids == [pa_id], str(ids))
    with engine.begin() as conn:  # 下架状态也要出现在自己的列表里
        conn.execute(sql("UPDATE projects SET status='taken_down' WHERE id=:p"), {"p": pa_id})
    r = c.get("/api/v1/me/projects", headers=author_auth)
    check("下架的项目自己仍可见", [x["id"] for x in r.json()["items"]] == [pa_id])
    check("下架的项目对外 404", c.get(f"/api/v1/projects/{pa_id}").status_code == 404)
    r = c.get(f"/api/v1/projects/{pa_id}", headers=author_auth)
    check("下架的项目作者本人详情可见", r.status_code == 200 and r.json()["status"] == "taken_down")
    with engine.begin() as conn:
        conn.execute(sql("UPDATE projects SET status='published' WHERE id=:p"), {"p": pa_id})

    print("== 5. 我的资料 / 兴趣 / 推送偏好 ==")
    r = c.get("/api/v1/me", headers=author_auth)
    check("GET /me = 200 且带手机号", r.status_code == 200 and r.json()["phone"], r.text[:200])
    r = c.patch("/api/v1/me", headers=author_auth,
                json={"nickname": "冒烟测试员", "bio": "我用 AI 做东西", "role": "developer",
                      "language_preference": "en-US", "interests": ["dev", "design"]})
    j = r.json()
    check("PATCH /me 全字段生效", r.status_code == 200 and j["nickname"] == "冒烟测试员"
          and j["role"] == "developer" and j["language_preference"] == "en-US"
          and sorted(j["interests"]) == ["design", "dev"], r.text[:300])
    r = c.patch("/api/v1/me", headers=author_auth, json={"nickname": None})
    check("传 null 不清空非空字段", r.json()["nickname"] == "冒烟测试员")
    r = c.post("/api/v1/me/interests", headers=author_auth, json={"interests": ["marketing"]})
    check("onboarding 写入兴趣 = 200", r.status_code == 200)
    check("兴趣已覆盖", c.get("/api/v1/me", headers=author_auth).json()["interests"] == ["marketing"])
    r = c.post("/api/v1/me/interests", headers=author_auth, json={"interests": []})
    check("空兴趣 = 422（至少选 1 个）", r.status_code == 422)
    r = c.post("/api/v1/me/interests", headers=author_auth, json={"interests": ["not_a_domain"]})
    check("非法领域值 = 422", r.status_code == 422)

    r = c.get("/api/v1/me/push-preferences", headers=author_auth)
    check("推送偏好首次访问 = 200 且默认全开", r.status_code == 200 and all(r.json().values()), r.text[:200])
    r = c.patch("/api/v1/me/push-preferences", headers=author_auth,
                json={"daily_pick_enabled": False, "how_to_interest_enabled": False})
    j = r.json()
    check("改两个开关：改的关了、没改的还开着",
          j["daily_pick_enabled"] is False and j["how_to_interest_enabled"] is False
          and j["clue_update_enabled"] is True, str(j))

    # ---- 清理本次测试数据（保持 dev 库干净）----
    with engine.begin() as conn:
        conn.execute(sql("""
            DELETE FROM project_tag_relations WHERE project_id IN
              (SELECT id FROM projects WHERE author_user_id = ANY(CAST(:u AS uuid[])))"""),
            {"u": created_user_ids})
        conn.execute(sql("DELETE FROM project_tags WHERE name LIKE '%冒烟%'"))
        conn.execute(sql("""
            DELETE FROM project_media WHERE project_id IN
              (SELECT id FROM projects WHERE author_user_id = ANY(CAST(:u AS uuid[])))
              OR project_id IS NULL"""), {"u": created_user_ids})
        conn.execute(sql("""
            DELETE FROM similar_project_links WHERE source_project_id IN
              (SELECT id FROM projects WHERE author_user_id = ANY(CAST(:u AS uuid[])))"""),
            {"u": created_user_ids})
        conn.execute(sql("DELETE FROM notifications WHERE user_id = ANY(CAST(:u AS uuid[]))"),
                     {"u": created_user_ids})
        conn.execute(sql("DELETE FROM projects WHERE author_user_id = ANY(CAST(:u AS uuid[]))"),
                     {"u": created_user_ids})
        conn.execute(sql("DELETE FROM push_preferences WHERE user_id = ANY(CAST(:u AS uuid[]))"),
                     {"u": created_user_ids})
        conn.execute(sql("DELETE FROM users WHERE id = ANY(CAST(:u AS uuid[]))"), {"u": created_user_ids})

    print(f"\n结果：{passed} 通过 / {failed} 失败")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
