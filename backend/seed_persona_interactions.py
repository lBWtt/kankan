# ============================================================
# 用 DeepSeek 让 200 个马甲在「项目 / 动态」下发**自然评论** + 楼中楼回复 + 点赞 + 收藏，
# 让 App 冷启动看起来有真人在互动。用户 2026-07-26。
#
# 说话风格：**当场取样现有动态的口吻**喂给模型（口语、简短、不彩虹屁），保持社区一致感。
# 通知：直接插库、**不走 create_comment 的互动通知**（否则给马甲刷屏几百条站内信）。
# 时间：评论时间落在「宿主发布之后 ~ 现在」之间，散开，不会出现评论早于内容。
#
# ⚠️ DEEPSEEK KEY 走环境变量，**不写进文件/不提交**：
#   本机： set DEEPSEEK_API_KEY=sk-xxx  然后 python seed_persona_interactions.py --max-hosts 50
#   生产： 部署后同样带 env 跑一次（去掉 --max-hosts 跑全量）
#
# 常用参数：
#   --max-hosts N   最多处理多少个宿主(项目+动态)，控制 DeepSeek 调用量/花费（默认全部）
#   --reset         先删掉所有马甲发的评论/赞/收藏再重灌（幂等重跑）
#   --dry           只打印将生成什么，不调 DeepSeek、不写库
# ============================================================
import argparse
import json
import os
import random
import re
import sys
from datetime import datetime, timedelta, timezone

from sqlalchemy import func, select

from app.core.config import settings
from app.core.db import SessionLocal
from app.models import (
    Comment, CommentLike, Favorite, Post, PostLike, Project,
    ProjectReaction, TryItem, User,
)
from app.services.personas import PERSONA_EMAIL_DOMAIN, persona_users

rng = random.Random(20260726)

# 创意反馈三种（与 enums.REACTION_TYPE 一致）
REACTIONS = ("creative", "big_brain", "cool")

# DeepSeek 已下线 deepseek-chat；现用 deepseek-v4-flash（快/省，短评论足够）。可用 env 覆盖。
MODEL = os.environ.get("DEEPSEEK_MODEL") or "deepseek-v4-flash"

_CJK = re.compile(r"[一-鿿]")


def _client():
    key = os.environ.get("DEEPSEEK_API_KEY") or settings.deepseek_api_key
    if not key:
        print("缺 DEEPSEEK_API_KEY（set DEEPSEEK_API_KEY=sk-xxx 后再跑）")
        sys.exit(1)
    from openai import OpenAI
    return OpenAI(api_key=key, base_url=settings.deepseek_base_url)


def _looks_real(text: str) -> bool:
    """过滤测试垃圾动态（jhkfkjsdhfkj / 534354）：要有 ≥4 个汉字。"""
    return len(_CJK.findall(text or "")) >= 4


def style_examples(db, n=14):
    posts = db.scalars(
        select(Post).where(Post.deleted_at.is_(None)).order_by(func.random()).limit(80)
    ).all()
    good = [p.content.strip() for p in posts if _looks_real(p.content)]
    rng.shuffle(good)
    return good[:n]


def _parse_array(text: str):
    """从模型输出里抠出字符串数组：容忍 ```json 围栏、前后废话。"""
    if not text:
        return []
    text = text.strip()
    text = re.sub(r"^```(?:json)?|```$", "", text, flags=re.MULTILINE).strip()
    start, end = text.find("["), text.rfind("]")
    if start != -1 and end != -1 and end > start:
        try:
            arr = json.loads(text[start:end + 1])
            return [str(x).strip() for x in arr if str(x).strip()]
        except Exception:
            pass
    # 退化：按行拆，去掉序号/符号
    lines = [re.sub(r'^[\s\-\d\.、"]+|["，,]+$', "", ln).strip() for ln in text.splitlines()]
    return [ln for ln in lines if _looks_real(ln)]


def gen_comments(client, examples, host_desc, k):
    prompt = (
        "你在一个中文 AI 创意作品社区里当普通用户。社区里大家发言的风格示例：\n"
        + "\n".join(f"- {e}" for e in examples)
        + f"\n\n现在针对下面这条内容，写 {k} 条**评论**。要求：像真人随手评论——"
        "口语、简短（多数 5~25 字）；有的夸、有的问细节、有的表示共鸣或想试试；"
        "别每条都商业互吹，别用话题标签(#)、别 @人、别加引号、别带序号。\n"
        f"内容：{host_desc}\n\n"
        "只输出一个 JSON 字符串数组，每个元素一条评论。"
    )
    resp = client.chat.completions.create(
        model=MODEL,
        messages=[{"role": "user", "content": prompt}],
        temperature=1.1, max_tokens=500,
    )
    out = _parse_array(resp.choices[0].message.content)
    return out[:k]


def _recent_after(host_created, now):
    """在 [宿主发布, 现在] 里取个随机时刻（最多回溯 12 天）。"""
    lo = max(host_created, now - timedelta(days=12))
    if lo >= now:
        return now
    delta = (now - lo).total_seconds()
    return lo + timedelta(seconds=rng.uniform(0, delta))


def reset_persona_interactions(db):
    pids = [p.id for p in persona_users(db)]
    if not pids:
        return
    idset = set(pids)
    # 删马甲发的评论（及其赞随之，靠外键/或手动）
    pc = db.scalars(select(Comment.id).where(Comment.author_user_id.in_(pids))).all()
    if pc:
        db.query(CommentLike).filter(CommentLike.comment_id.in_(pc)).delete(synchronize_session=False)
        db.query(Comment).filter(Comment.id.in_(pc)).delete(synchronize_session=False)
    db.query(CommentLike).filter(CommentLike.user_id.in_(pids)).delete(synchronize_session=False)
    db.query(PostLike).filter(PostLike.user_id.in_(pids)).delete(synchronize_session=False)
    db.query(Favorite).filter(Favorite.user_id.in_(pids)).delete(synchronize_session=False)
    db.query(TryItem).filter(TryItem.user_id.in_(pids)).delete(synchronize_session=False)
    db.query(ProjectReaction).filter(ProjectReaction.user_id.in_(pids)).delete(synchronize_session=False)
    db.commit()
    print(f"--reset：已清马甲评论 {len(pc)} 条及相关赞/收藏/体验/反馈")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--max-hosts", type=int, default=0, help="最多处理多少宿主(0=全部)")
    ap.add_argument("--reset", action="store_true")
    ap.add_argument("--dry", action="store_true")
    args = ap.parse_args()

    db = SessionLocal()
    try:
        if args.reset and not args.dry:
            reset_persona_interactions(db)

        personas = persona_users(db)
        if len(personas) < 5:
            print("马甲不足，先跑 seed_personas.py"); return
        pid_set = {p.id for p in personas}
        examples = style_examples(db)
        if not examples:
            print("没有可参考的真实动态风格，先有点动态再跑"); return

        projects = db.scalars(
            select(Project).where(Project.status == "published", Project.deleted_at.is_(None))
        ).all()
        posts = db.scalars(select(Post).where(Post.deleted_at.is_(None))).all()
        posts = [p for p in posts if _looks_real(p.content)]  # 不给测试垃圾动态灌评论

        hosts = ([("project", p) for p in projects] + [("post", p) for p in posts])
        rng.shuffle(hosts)
        if args.max_hosts > 0:
            hosts = hosts[:args.max_hosts]

        client = None if args.dry else _client()
        now = datetime.now(timezone.utc)
        n_comments = n_replies = n_clikes = n_plikes = n_favs = n_tries = n_reactions = 0

        for i, (htype, host) in enumerate(hosts):
            k = rng.randint(2, 6)
            pool = [p for p in personas if p.id != host.author_user_id]
            commenters = rng.sample(pool, min(k, len(pool)))
            if htype == "project":
                desc = f"项目《{host.title}》：{host.tagline or ''}。{(host.summary or '')[:120]}"
            else:
                desc = f"一条动态：{host.content[:140]}"

            if args.dry:
                print(f"[{htype}] {desc[:50]}… → 生成 {k} 条评论")
                n_comments += k
                continue

            try:
                texts = gen_comments(client, examples, desc, k)
            except Exception as exc:
                print(f"  DeepSeek 失败（{htype} {str(host.id)[:8]}）：{exc}")
                continue

            top_comments = []
            for persona, text in zip(commenters, texts):
                if not _looks_real(text):
                    continue
                c = Comment(
                    host_type=htype, host_id=host.id, author_user_id=persona.id,
                    content=text[:280], created_at=_recent_after(host.created_at, now),
                )
                db.add(c); db.flush()
                top_comments.append(c)
                n_comments += 1
                # 评论赞：给这条评论随机几个马甲赞
                likers = rng.sample(personas, min(rng.randint(0, 12), len(personas)))
                cl = 0
                for lk in likers:
                    if lk.id == persona.id:
                        continue
                    db.add(CommentLike(comment_id=c.id, user_id=lk.id)); cl += 1
                c.like_count = cl
                n_clikes += cl

            # 楼中楼：~40% 的宿主，给某条顶级评论来一条回复
            if top_comments and rng.random() < 0.4:
                parent = rng.choice(top_comments)
                replier = rng.choice([p for p in personas if p.id != parent.author_user_id])
                try:
                    rtexts = gen_comments(client, examples, f"回复评论「{parent.content}」（就内容简短接话）", 1)
                except Exception:
                    rtexts = []
                if rtexts and _looks_real(rtexts[0]):
                    db.add(Comment(
                        host_type=htype, host_id=host.id, author_user_id=replier.id,
                        content=rtexts[0][:280], parent_comment_id=parent.id,
                        created_at=_recent_after(parent.created_at, now),
                    ))
                    n_replies += 1

            # 点赞 / 收藏
            fans = rng.sample(personas, min(rng.randint(3, 30), len(personas)))
            if htype == "post":
                cnt = 0
                for f in fans:
                    if f.id == host.author_user_id:
                        continue
                    db.add(PostLike(post_id=host.id, user_id=f.id)); cnt += 1
                host.like_count = (host.like_count or 0) + cnt
                n_plikes += cnt
            else:
                for f in fans:
                    if f.id == host.author_user_id:
                        continue
                    db.add(Favorite(project_id=host.id, user_id=f.id)); n_favs += 1
                # 体验（想试）：比收藏少——真人里"点进去玩"的比"顺手收藏"的少
                triers = rng.sample(personas, min(rng.randint(2, 15), len(personas)))
                seen_try = set()
                for t in triers:
                    if t.id == host.author_user_id or t.id in seen_try:
                        continue
                    seen_try.add(t.id)
                    db.add(TryItem(project_id=host.id, user_id=t.id)); n_tries += 1
                # 创意反馈（有创意/太聪明了/酷）：随机几个马甲各挑一种
                reactors = rng.sample(personas, min(rng.randint(2, 18), len(personas)))
                seen_react = set()
                for r in reactors:
                    if r.id == host.author_user_id or r.id in seen_react:
                        continue
                    seen_react.add(r.id)
                    db.add(ProjectReaction(
                        project_id=host.id, user_id=r.id,
                        reaction_type=rng.choice(REACTIONS),
                    )); n_reactions += 1

            if i % 10 == 0:
                db.commit()
                print(f"  ...{i + 1}/{len(hosts)}（评论 {n_comments}）")

        db.commit()
        print(f"完成：评论 {n_comments}、回复 {n_replies}、评论赞 {n_clikes}、"
              f"动态赞 {n_plikes}、收藏 {n_favs}、体验 {n_tries}、反馈 {n_reactions}"
              f"（宿主 {len(hosts)}）")
    finally:
        db.close()


if __name__ == "__main__":
    main()
