# ============================================================
# 这个文件是干什么的：健壮性补丁的冒烟测试——两项：①验证码猜码次数锁（连错够数就锁，防撞库）、
#   ②榜单 Redis 缓存被写脏时 /rankings 不 500（降级重算）。
# 它对应产品里的什么功能：登录安全、榜单页在缓存异常时仍能打开。
# 如果它出错了，用户会看到什么现象：开发者上线前就拦住——这正是它存在的目的。
# 用法：先起服务（uvicorn app.main:app），再在 backend/ 下（设 PYTHONPATH=.）跑：
#   .venv/Scripts/python.exe -X utf8 tests/smoke_v9.py [BASE_URL，默认 http://127.0.0.1:8000]
# ============================================================
import sys
import time

import httpx
from sqlalchemy import text as sql

from app.core.db import engine
from app.core.redis import redis_client
from app.services.rankings import _CACHE_KEY

BASE = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8000"

passed, failed = 0, 0
user_ids, phones = [], []


def check(name: str, cond: bool, extra=""):
    global passed, failed
    if cond:
        passed += 1
        print(f"  PASS  {name}")
    else:
        failed += 1
        print(f"  FAIL  {name}  {extra}")


def fresh_phone(prefix):
    p = f"{prefix}{int(time.time() * 1000) % 100000000:08d}"
    phones.append(p)
    redis_client.delete(f"authfail:phone:{p}")  # 清残留计数，保证重跑可复现
    redis_client.delete(f"authcode:phone:{p}")
    time.sleep(0.002)
    return p


def login(c, phone, code):
    return c.post("/api/v1/auth/login", json={"identifier_type": "phone", "identifier": phone, "code": code})


def main():
    c = httpx.Client(base_url=BASE, timeout=20, trust_env=False)  # trust_env=False 绕过本机代理
    check("GET /health = 200", c.get("/health").status_code == 200)

    print("== 1. 验证码猜码次数锁 ==")
    p1 = fresh_phone("133")
    codes = [login(c, p1, "000000").status_code for _ in range(5)]
    check("连错 5 次每次都是 422（未锁前正常拒）", codes == [422] * 5, str(codes))
    r = login(c, p1, "000000")
    check("第 6 次 = 429 RATE_LIMITED（已锁定）",
          r.status_code == 429 and r.json()["code"] == "RATE_LIMITED", r.text[:200])
    r = login(c, p1, "888888")
    check("锁定期内连正确万能码也被拦 = 429", r.status_code == 429, r.text[:200])

    p2 = fresh_phone("132")
    r = login(c, p2, "888888")
    check("另一手机号不受影响 = 200（锁按标识隔离）", r.status_code == 200, r.text[:200])
    if r.status_code == 200:
        user_ids.append(r.json()["user"]["id"])

    p3 = fresh_phone("131")
    [login(c, p3, "000000") for _ in range(3)]  # 错 3 次
    r = login(c, p3, "888888")
    check("错 3 次后成功登录 = 200", r.status_code == 200, r.text[:200])
    if r.status_code == 200:
        user_ids.append(r.json()["user"]["id"])
    r = login(c, p3, "000000")
    check("成功登录已清零计数：再错仍是 422 不是 429", r.status_code == 422, r.text[:200])

    print("== 2. 榜单缓存被写脏时不 500 ==")
    r = c.get("/api/v1/rankings", params={"type": "weekly_hot", "limit": 10})
    check("正常榜单 = 200（基线）", r.status_code == 200, r.text[:200])

    redis_client.set(_CACHE_KEY, "garbage{not json")
    r = c.get("/api/v1/rankings", params={"type": "weekly_hot", "limit": 10})
    check("缓存=坏 JSON → 200 降级重算（非 500）", r.status_code == 200, r.text[:200])
    check("坏缓存键已被清除（不让后续请求一直踩）", redis_client.get(_CACHE_KEY) != "garbage{not json")

    redis_client.set(_CACHE_KEY, '["not-a-uuid", "也不是uuid"]')
    r = c.get("/api/v1/rankings", params={"type": "weekly_hot", "limit": 10})
    check("缓存=合法 JSON 但非 UUID → 200 降级重算（非 500）", r.status_code == 200, r.text[:200])

    redis_client.set(_CACHE_KEY, '"a string not a list"')
    r = c.get("/api/v1/rankings", params={"type": "weekly_hot", "limit": 10})
    check("缓存=JSON 字符串非数组 → 200（非 500）", r.status_code == 200, r.text[:200])

    # ---- 清理 ----
    redis_client.delete(_CACHE_KEY)
    for p in phones:
        redis_client.delete(f"authfail:phone:{p}")
        redis_client.delete(f"authcode:phone:{p}")
    with engine.begin() as conn:
        for uid in user_ids:
            conn.execute(sql("DELETE FROM push_preferences WHERE user_id = CAST(:u AS uuid)"), {"u": uid})
            conn.execute(sql("DELETE FROM users WHERE id = CAST(:u AS uuid)"), {"u": uid})

    print(f"\n结果：{passed} 通过 / {failed} 失败")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
