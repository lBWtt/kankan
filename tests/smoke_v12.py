# ============================================================
# 这个文件是干什么的：阶段2「评论」的端到端冒烟——发/回复(楼中楼)/点赞/列表(is_liked)/删/校验。
# 它对应产品里的什么功能：项目详情评论区。
# 用法：先起服务，再在 backend/ 下：.venv/Scripts/python.exe -X utf8 tests/smoke_v12.py
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
    return c.post(f"{API}/auth/login", json={"identifier_type": "email", "identifier": email, "code": "888888"}).json()["access_token"]


def main():
    with httpx.Client(timeout=10, trust_env=False) as c:
        sfx = uuidlib.uuid4().hex[:8]
        tokA = login(c, f"cmtsm_a_{sfx}@test.com")
        tokB = login(c, f"cmtsm_b_{sfx}@test.com")
        hA = {"Authorization": f"Bearer {tokA}"}
        hB = {"Authorization": f"Bearer {tokB}"}
        pid = c.get(f"{API}/projects?limit=1").json()["items"][0]["id"]

        r = c.post(f"{API}/comments", headers=hA, json={"host_type": "project", "host_id": pid, "content": "冒烟顶级评论"})
        check("发顶级评论 = 201", r.status_code == 201, r.text[:120])
        c1 = r.json()
        check("评论带真作者", c1.get("author") and c1["author"].get("id"), str(c1.get("author")))
        cid = c1["id"]

        r = c.post(f"{API}/comments", headers=hB, json={"host_type": "project", "host_id": pid, "content": "冒烟回复", "parent_comment_id": cid})
        check("楼中楼回复 = 201", r.status_code == 201, r.text[:120])
        rid = r.json()["id"]

        r = c.post(f"{API}/comments", headers=hA, json={"host_type": "project", "host_id": pid, "content": "回复回复", "parent_comment_id": rid})
        check("回复子回复 = 422（楼中楼仅一层）", r.status_code == 422, r.text[:120])

        r = c.post(f"{API}/comments", headers=hA, json={"host_type": "project", "host_id": str(uuidlib.uuid4()), "content": "不存在项目"})
        check("宿主项目不存在 = 404", r.status_code == 404, r.text[:120])

        check("B 给评论点赞 = 201", c.post(f"{API}/comments/{cid}/like", headers=hB).status_code == 201)
        check("重复点赞幂等 = 201", c.post(f"{API}/comments/{cid}/like", headers=hB).status_code == 201)

        lst = c.get(f"{API}/comments?host_type=project&host_id={pid}", headers=hB).json()
        mine = [x for x in lst["items"] if x["id"] == cid]
        check("列表含该顶级评论", len(mine) == 1, str(len(lst["items"])))
        if mine:
            check("首条 likes = 1", mine[0]["likes"] == 1, str(mine[0]["likes"]))
            check("首条 is_liked(B) = true", mine[0]["is_liked"] is True, str(mine[0]["is_liked"]))
            check("首条内嵌 1 条回复", len(mine[0]["replies"]) == 1, str(len(mine[0]["replies"])))
        # 游客看 is_liked=false
        g = c.get(f"{API}/comments?host_type=project&host_id={pid}").json()
        gm = [x for x in g["items"] if x["id"] == cid]
        check("游客 is_liked = false", gm and gm[0]["is_liked"] is False, str(gm[0]["is_liked"] if gm else None))

        check("取消点赞 = 204", c.delete(f"{API}/comments/{cid}/like", headers=hB).status_code == 204)
        check("A 删他人评论 = 403", c.delete(f"{API}/comments/{rid}", headers=hA).status_code == 403)
        check("A 删自己评论 = 204", c.delete(f"{API}/comments/{cid}", headers=hA).status_code == 204)

    print(f"\n结果：{passed} 通过 / {failed} 失败")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
