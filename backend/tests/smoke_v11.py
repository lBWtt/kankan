# ============================================================
# 这个文件是干什么的：阶段1「关注」的端到端冒烟测试——对着真实运行的服务，
#   跑一遍 关注→幂等→关注自己409→计数→粉丝/关注列表→取关 的完整链路。
# 它对应产品里的什么功能：我的页关注/粉丝数、个人主页关注按钮、关注/粉丝列表。
# 如果它出错了：开发者上线前发现问题。
# 用法：先起服务，再在 backend/ 下：.venv/Scripts/python.exe -X utf8 tests/smoke_v11.py
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
    r = c.post(f"{API}/auth/login", json={"identifier_type": "email", "identifier": email, "code": "888888"})
    d = r.json()
    return d["access_token"], d["user"]["id"]


def main():
    with httpx.Client(timeout=10, trust_env=False) as c:
        # 两个全新用户（随机邮箱，避免复用旧数据）
        sfx = uuidlib.uuid4().hex[:8]
        tokA, idA = login(c, f"followsm_a_{sfx}@test.com")
        tokB, idB = login(c, f"followsm_b_{sfx}@test.com")
        hA = {"Authorization": f"Bearer {tokA}"}
        hB = {"Authorization": f"Bearer {tokB}"}

        r = c.post(f"{API}/users/{idB}/follow", headers=hA)
        check("A 关注 B = 201", r.status_code == 201, r.text[:120])
        r = c.post(f"{API}/users/{idB}/follow", headers=hA)
        check("重复关注幂等 = 201", r.status_code == 201, r.text[:120])
        r = c.post(f"{API}/users/{idA}/follow", headers=hA)
        check("关注自己 = 409 CANNOT_FOLLOW_SELF",
              r.status_code == 409 and r.json().get("code") == "CANNOT_FOLLOW_SELF", r.text[:120])

        me = c.get(f"{API}/me", headers=hA).json()
        check("A /me following_count = 1", me.get("following_count") == 1, str(me.get("following_count")))
        check("A /me follower_count = 0", me.get("follower_count") == 0, str(me.get("follower_count")))

        bp = c.get(f"{API}/users/{idB}", headers=hA).json()
        check("B 主页 follower_count = 1", bp.get("follower_count") == 1, str(bp.get("follower_count")))
        check("B 主页 is_followed_by_me(A) = true", bp.get("is_followed_by_me") is True, str(bp.get("is_followed_by_me")))
        # 游客视角 is_followed_by_me = false
        bp_guest = c.get(f"{API}/users/{idB}").json()
        check("游客看 B is_followed_by_me = false", bp_guest.get("is_followed_by_me") is False, str(bp_guest.get("is_followed_by_me")))

        fl = c.get(f"{API}/users/{idB}/followers").json()
        check("B 粉丝列表含 A", any(u["id"] == idA for u in fl.get("items", [])), str(fl.get("items")))
        fw = c.get(f"{API}/users/{idA}/following").json()
        check("A 关注列表含 B", any(u["id"] == idB for u in fw.get("items", [])), str(fw.get("items")))

        r = c.delete(f"{API}/users/{idB}/follow", headers=hA)
        check("A 取关 B = 204", r.status_code == 204, r.text[:120])
        r = c.delete(f"{API}/users/{idB}/follow", headers=hA)
        check("重复取关幂等 = 204", r.status_code == 204, r.text[:120])
        me2 = c.get(f"{API}/me", headers=hA).json()
        check("取关后 A following_count = 0", me2.get("following_count") == 0, str(me2.get("following_count")))

    print(f"\n结果：{passed} 通过 / {failed} 失败")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
