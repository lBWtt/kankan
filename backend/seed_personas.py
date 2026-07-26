# ============================================================
# 建/更新站内「马甲号」——approve 外部内容时按人设自动派一个当作者，让内容像真人发的。
# 共 200 个马甲，分 10 套人设（见 app/services/persona_archetypes.py），每套 20 个，男女名混搭。
#
# ⚠️ upsert（用户 2026-07-26）：已存在的马甲**也会更新** nickname/bio ——
#   因为要把历史「明说人设」的名字（画画的小满/写代码的老K）刷成潜在正常人名。
#   只改 nickname/bio，不动 email/handle/内容/头像。
#
# 跑：python seed_personas.py            # 建缺的 + 刷新已有名字/签名（潜在风）
#     python seed_persona_follows.py     # 再建互关关系（粉丝数）
#     python seed_avatars.py             # 再补头像
# ============================================================
import random

from app.core.db import SessionLocal
from app.models import User
from app.services.personas import PERSONA_EMAIL_DOMAIN
from app.services.persona_archetypes import (
    ARCHETYPES,
    OLD_PERSONA_ARCHETYPE,
    MALE_NAMES,
    FEMALE_NAMES,
    NEUTRAL_NAMES,
)

TARGET_PER_ARCHETYPE = 20  # 每套人设 20 个 → 10 套 × 20 = 200

# 5 个老马甲（有内容，email 不能动）。名字/签名也换成潜在正常人名（不再明说人设）。
ORIGINAL_PERSONAS = [
    ("amay", "江屿", "对颜色和光比较敏感"),
    ("shiguang", "沈砚", "喜欢用镜头记录"),
    ("laok", "白术", "一个人做产品"),
    ("linshen", "顾湘", "把日子过得方便一点"),
    ("zaowuzhi", "陆时", "在做点小生意"),
]


def build_new_personas():
    """产出要新建的 195 个马甲：[(email, nickname, bio)]，每套人设补齐到 20 个。
    名字男女交替，从潜在正常人名池取；固定随机种子，结果可复现。"""
    old_count = {}
    for arch in OLD_PERSONA_ARCHETYPE.values():
        old_count[arch] = old_count.get(arch, 0) + 1

    rng = random.Random(20260726)
    males, females, neutral = MALE_NAMES[:], FEMALE_NAMES[:], NEUTRAL_NAMES[:]
    rng.shuffle(males)
    rng.shuffle(females)
    rng.shuffle(neutral)

    out = []
    gender_toggle = 0
    for arch, cfg in ARCHETYPES.items():
        need = TARGET_PER_ARCHETYPE - old_count.get(arch, 0)
        for i in range(need):
            pool = males if gender_toggle % 2 == 0 else females
            if not pool:
                pool = females if females else males
            name = pool.pop()
            gender_toggle += 1
            bio = cfg["bios"][i % len(cfg["bios"])]
            email = f"{arch}{i + 1:02d}@{PERSONA_EMAIL_DOMAIN}"
            out.append((email, name, bio))
    return out


def main() -> None:
    db = SessionLocal()
    created = updated = 0
    try:
        plan = [(f"{k}@{PERSONA_EMAIL_DOMAIN}", nick, bio) for k, nick, bio in ORIGINAL_PERSONAS]
        plan += build_new_personas()

        # 全局唯一昵称：先占用「非马甲」用户已用的昵称，马甲之间也去重。
        persona_emails = {email for email, _, _ in plan}
        taken_nicks = {
            n for (n, e) in db.query(User.nickname, User.email).all()
            if n and (e not in persona_emails)  # 马甲自己的旧名不算占用（要被覆盖）
        }

        for email, nickname, bio in plan:
            nick = nickname
            while nick in taken_nicks:  # 撞名兜底
                nick += "·"
            taken_nicks.add(nick)

            user = db.query(User).filter(User.email == email).first()
            if user is None:
                db.add(User(
                    email=email, nickname=nick, avatar_url=None,
                    bio=bio, role="creator", is_admin=False,
                ))
                created += 1
            else:
                # upsert：刷新名字/签名成潜在风；不动 handle/头像/内容
                if user.nickname != nick or user.bio != bio:
                    user.nickname = nick
                    user.bio = bio
                    updated += 1

        db.commit()
        total = (
            db.query(User)
            .filter(User.email.like(f"%@{PERSONA_EMAIL_DOMAIN}"), User.deleted_at.is_(None))
            .count()
        )
        print(f"马甲：新建 {created}，改名/签名 {updated}；当前马甲总数 {total}")
        print("下一步：python seed_persona_follows.py  # 建互关；python seed_avatars.py  # 补头像")
    finally:
        db.close()


if __name__ == "__main__":
    main()
