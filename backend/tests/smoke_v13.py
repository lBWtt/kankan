# ============================================================
# 这个文件是干什么的：阶段3「动态」的端到端冒烟——发/流/详情/点赞/评论动态/某人动态/删/校验。
# 它对应产品里的什么功能：发现页动态流、发动态、动态详情、动态点赞。
# 用法：先起服务，再在 backend/ 下：.venv/Scripts/python.exe -X utf8 tests/smoke_v13.py
# ============================================================
import sys
import uuid as uuidlib

import httpx

BASE = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8000"
API = BASE + "/api/v1"
passed, failed = 0, 0


def check(name, cond, extra=""):
    global passed, failed
    if cond:
        passed += 1
        print(f"  PASS  {name}")
    else:
        failed += 1
        print(f"  FAIL  {name}  {extra}")


def login(c, email):
    return c.post(f"{API}/auth/login", json={"identifier_type": "email", "identifier": email, "code": "888888"}).json()


def main():
    with httpx.Client(timeout=10, trust_env=False) as c:
        sfx = uuidlib.uuid4().hex[:8]
        a = login(c, f"postsm_a_{sfx}@test.com")
        tokA, uidA = a["access_token"], a["user"]["id"]
        tokB = login(c, f"postsm_b_{sfx}@test.com")["access_token"]
        hA = {"Authorization": f"Bearer {tokA}"}
        hB = {"Authorization": f"Bearer {tokB}"}
        pid = c.get(f"{API}/projects?limit=1").json()["items"][0]["id"]

        r = c.post(f"{API}/posts", headers=hA, json={"content": "冒烟动态", "tags": ["flutter"], "quote_project_id": pid})
        check("发动态 = 201", r.status_code == 201, r.text[:120])
        p = r.json()
        check("动态带真作者", p.get("author") and p["author"].get("id"), str(p.get("author")))
        check("tags 落表", p.get("tags") == ["flutter"], str(p.get("tags")))
        check("引用项目落表", str(p.get("quote_project_id")) == pid, str(p.get("quote_project_id")))
        postid = p["id"]

        feed = c.get(f"{API}/posts?limit=10").json()
        check("动态流含新动态", any(x["id"] == postid for x in feed["items"]), str(len(feed["items"])))

        check("B 点赞动态 = 201", c.post(f"{API}/posts/{postid}/like", headers=hB).status_code == 201)
        check("重复点赞幂等 = 201", c.post(f"{API}/posts/{postid}/like", headers=hB).status_code == 201)

        r = c.post(f"{API}/comments", headers=hB, json={"host_type": "post", "host_id": postid, "content": "评论动态"})
        check("评论动态(host=post) = 201", r.status_code == 201, r.text[:120])

        pd = c.get(f"{API}/posts/{postid}", headers=hB).json()
        check("详情 likes = 1", pd["likes"] == 1, str(pd["likes"]))
        check("详情 is_liked(B) = true", pd["is_liked"] is True, str(pd["is_liked"]))
        check("详情 comment_count = 1", pd["comment_count"] == 1, str(pd["comment_count"]))

        up = c.get(f"{API}/users/{uidA}/posts").json()
        check("A 的动态列表含该动态", any(x["id"] == postid for x in up["items"]), str(len(up["items"])))

        check("评论不存在的动态 = 404", c.post(f"{API}/comments", headers=hA, json={"host_type": "post", "host_id": str(uuidlib.uuid4()), "content": "x"}).status_code == 404)
        check("取消点赞 = 204", c.delete(f"{API}/posts/{postid}/like", headers=hB).status_code == 204)
        check("B 删A的动态 = 403", c.delete(f"{API}/posts/{postid}", headers=hB).status_code == 403)
        check("A 删自己动态 = 204", c.delete(f"{API}/posts/{postid}", headers=hA).status_code == 204)
        check("删后详情 = 404", c.get(f"{API}/posts/{postid}").status_code == 404)

    print(f"\n结果：{passed} 通过 / {failed} 失败")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
