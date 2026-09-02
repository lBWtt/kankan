# ============================================================
# 给 200 个马甲建「互相关注」关系——让每个号有像样的关注/粉丝数，App 里不显得空号。
# 用户 2026-07-26：马甲相互关注增加关注数/粉丝数；每个号粉丝 ≤200（200 个马甲天然 ≤199）。
#
# 关系不是全互关（那样每人都 199 粉太假），用「优先连接」加权采样：
#   少数号很受欢迎(粉丝多)、多数中等、少数冷门——粉丝数呈自然的长尾分布。
# 幂等：已存在的 (follower,followee) 跳过；只在马甲之间建，不碰真实用户。
#
# 跑：python seed_persona_follows.py            # 建关系（默认）
#     python seed_persona_follows.py --reset    # 先清空马甲间关系再重建
# ============================================================
import random
import sys

from sqlalchemy import insert, select

from app.core.db import SessionLocal
from app.models import UserFollow
from app.services.personas import persona_users

FOLLOW_MIN = 15   # 每个号至少主动关注多少人
FOLLOW_MAX = 90   # 至多
FOLLOWER_CAP = 200  # 粉丝数硬上限（安全阀，正常到不了）


def weighted_sample(candidates, weights, k, rng):
    """按权重不放回地采 k 个（优先连接：权重高的更容易被关注）。"""
    chosen, seen = [], set()
    pool = candidates[:]
    w = [weights[c] for c in pool]
    tries = 0
    while len(chosen) < k and pool and tries < k * 40:
        tries += 1
        pick = rng.choices(pool, weights=w, k=1)[0]
        if pick in seen:
            continue
        seen.add(pick)
        chosen.append(pick)
    return chosen


def main() -> None:
    reset = "--reset" in sys.argv
    db = SessionLocal()
    try:
        personas = persona_users(db)
        ids = [p.id for p in personas]
        n = len(ids)
        if n < 2:
            print(f"马甲不足（{n}），先跑 seed_personas.py")
            return

        rng = random.Random(20260726)
        # 优先连接权重：帕累托长尾——少数号权重很高（会成大V），多数普通。
        weights = {i: rng.paretovariate(1.3) for i in ids}

        if reset:
            id_set = set(ids)
            # 只删马甲之间的关注（保留真实用户关注马甲的关系）
            rows = db.execute(select(UserFollow.id, UserFollow.follower_user_id,
                                     UserFollow.followee_user_id)).all()
            del_ids = [r.id for r in rows
                       if r.follower_user_id in id_set and r.followee_user_id in id_set]
            if del_ids:
                db.query(UserFollow).filter(UserFollow.id.in_(del_ids)).delete(synchronize_session=False)
                db.commit()
            print(f"--reset：清掉马甲间旧关注 {len(del_ids)} 条")

        # 已有的 (follower,followee) 对，避免撞唯一约束
        existing = set(
            (a, b) for a, b in db.execute(
                select(UserFollow.follower_user_id, UserFollow.followee_user_id)
            ).all()
        )
        follower_count = {i: 0 for i in ids}
        for a, b in existing:
            if b in follower_count:
                follower_count[b] += 1

        new_rows = []
        for follower in ids:
            k = rng.randint(FOLLOW_MIN, FOLLOW_MAX)
            candidates = [i for i in ids if i != follower]
            for followee in weighted_sample(candidates, weights, k, rng):
                if (follower, followee) in existing:
                    continue
                if follower_count[followee] >= FOLLOWER_CAP:
                    continue
                existing.add((follower, followee))
                follower_count[followee] += 1
                new_rows.append({"follower_user_id": follower, "followee_user_id": followee})

        if new_rows:
            db.execute(insert(UserFollow), new_rows)
            db.commit()

        counts = sorted(follower_count.values(), reverse=True)
        print(f"新建关注 {len(new_rows)} 条；马甲 {n} 个")
        print(f"粉丝数分布：最高 {counts[0]}，中位 {counts[n // 2]}，最低 {counts[-1]}")
    finally:
        db.close()


if __name__ == "__main__":
    main()
