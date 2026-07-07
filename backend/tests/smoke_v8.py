# ============================================================
# 这个文件是干什么的：安全收尾的冒烟测试——三项：①媒体上传者归属（别人传的暂存图你挂不上）、
#   ②上传文件字节头校验（伪装文件挡在门外）、③刷新令牌轮换吊销（旧 refresh 用过即废）。
# 它对应产品里的什么功能：发布挂图的越权防护、上传安全、被窃登录令牌的止损。
# 如果它出错了，用户会看到什么现象：开发者上线前就拦住——这正是它存在的目的。
# 用法：先起服务（uvicorn app.main:app），再在 backend/ 下（设 PYTHONPATH=.）跑：
#   .venv/Scripts/python.exe -X utf8 tests/smoke_v8.py [BASE_URL，默认 http://127.0.0.1:8000]
# ============================================================
import base64
import sys
import time

import httpx
from sqlalchemy import text as sql

from app.core.db import engine

BASE = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8000"
MARK = f"v8_{int(time.time()) % 100000}"
PNG_1PX = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
)

passed, failed = 0, 0
user_ids, project_ids = [], []


def check(name: str, cond: bool, extra=""):
    global passed, failed
    if cond:
        passed += 1
        print(f"  PASS  {name}")
    else:
        failed += 1
        print(f"  FAIL  {name}  {extra}")


def login(c, prefix):
    phone = f"{prefix}{int(time.time() * 1000) % 100000000:08d}"
    r = c.post("/api/v1/auth/login", json={"identifier_type": "phone", "identifier": phone, "code": "888888"})
    body = r.json()
    user_ids.append(body["user"]["id"])
    return body["user"]["id"], {"Authorization": f"Bearer {body['access_token']}"}, body


def upload(c, auth) -> str:
    r = c.post("/api/v1/media", headers=auth, files={"file": ("a.png", PNG_1PX, "image/png")})
    assert r.status_code == 201, r.text
    return r.json()["id"]


def payload(media_ids):
    return {
        "title": f"{MARK} 安全测试项目", "tagline": "用 AI 一晚上做出可用工具",
        "summary": "这是一段超过二十个字的项目简介，描述这个 AI 用例做了什么、为什么值得一看。",
        "description": "完整复现步骤：先用脚手架生成骨架，再接 API，最后一键部署上线。",
        "category": "automation_tools", "domains": ["dev"], "tools": ["Claude Code"],
        "media_ids": media_ids, "is_original": True, "tags": [f"{MARK}标签"],
    }


def main():
    c = httpx.Client(base_url=BASE, timeout=20, trust_env=False)  # trust_env=False 绕过本机代理
    check("GET /health = 200", c.get("/health").status_code == 200)

    print("== 1. 媒体上传者归属（跨用户挂载越权）==")
    a_uid, a_auth, _ = login(c, "138")
    b_uid, b_auth, _ = login(c, "137")
    media_a = upload(c, a_auth)  # A 上传的暂存媒体

    r = c.post("/api/v1/projects", headers=b_auth, json=payload([media_a]))
    check("B 用 A 上传的暂存媒体发布 = 422（非本人上传被拦）",
          r.status_code == 422 and r.json()["code"] == "VALIDATION_FAILED"
          and media_a in r.json()["details"]["invalid_media_ids"], r.text[:250])

    r = c.post("/api/v1/projects", headers=a_auth, json=payload([media_a]))
    check("A 用自己的媒体发布 = 201（本人不受影响）", r.status_code == 201, r.text[:250])
    if r.status_code == 201:
        project_ids.append(r.json()["id"])

    print("== 2. 上传文件字节头校验（伪装文件）==")
    r = c.post("/api/v1/media", headers=a_auth, files={"file": ("real.png", PNG_1PX, "image/png")})
    check("真 PNG 字节 + image/png = 201", r.status_code == 201, r.text[:200])
    fake = b"<html><script>alert(1)</script></html>"
    r = c.post("/api/v1/media", headers=a_auth, files={"file": ("evil.png", fake, "image/png")})
    check("HTML 伪装成 image/png = 422（内容与类型不符）",
          r.status_code == 422 and "不符" in r.json()["message"], r.text[:200])
    r = c.post("/api/v1/media", headers=a_auth,
               files={"file": ("evil.mp4", b"not a real video file at all", "video/mp4")})
    check("假 mp4（无 ftyp box）= 422", r.status_code == 422, r.text[:200])

    print("== 3. 刷新令牌轮换 + 吊销 ==")
    _, _, lb = login(c, "136")
    r1 = lb["refresh_token"]
    r = c.post("/api/v1/auth/refresh", json={"refresh_token": r1})
    check("旧 refresh 首次刷新 = 200 且换发新令牌",
          r.status_code == 200 and r.json()["refresh_token"] != r1, r.text[:200])
    r2 = r.json()["refresh_token"]

    r = c.post("/api/v1/auth/refresh", json={"refresh_token": r1})
    check("同一旧 refresh 再用 = 401（已轮换吊销，被窃也无法续命）",
          r.status_code == 401 and r.json()["code"] == "AUTH_REQUIRED", r.text[:200])

    r = c.post("/api/v1/auth/refresh", json={"refresh_token": r2})
    check("最新 refresh 仍可用 = 200", r.status_code == 200, r.text[:200])

    r = c.post("/api/v1/auth/refresh", json={"refresh_token": "not.a.token"})
    check("伪造 refresh = 401", r.status_code == 401)

    # ---- 清理 ----
    with engine.begin() as conn:
        for pid in project_ids:
            conn.execute(sql("DELETE FROM project_tag_relations WHERE project_id = CAST(:p AS uuid)"), {"p": pid})
            conn.execute(sql("UPDATE project_media SET project_id = NULL WHERE project_id = CAST(:p AS uuid)"), {"p": pid})
        conn.execute(sql("DELETE FROM project_tags WHERE name = :nm"), {"nm": f"{MARK}标签"})
        for pid in project_ids:
            conn.execute(sql("DELETE FROM projects WHERE id = CAST(:p AS uuid)"), {"p": pid})
        for uid in user_ids:
            conn.execute(sql("DELETE FROM project_media WHERE uploader_user_id = CAST(:u AS uuid)"), {"u": uid})
            conn.execute(sql("DELETE FROM push_preferences WHERE user_id = CAST(:u AS uuid)"), {"u": uid})
            conn.execute(sql("DELETE FROM users WHERE id = CAST(:u AS uuid)"), {"u": uid})

    print(f"\n结果：{passed} 通过 / {failed} 失败")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
