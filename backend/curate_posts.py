# ============================================================
# 这个文件是干什么的：给「发现」动态流灌几条多类型示例动态（九宫格/单图/多图/纯文字/GIF），
#   让发现页有血有肉、演示各种配图布局。配图从 Picsum 下载真实照片转存本地（离线可显），
#   GIF 用 PIL 本地生成（真动图）。
# 它对应产品里的什么功能：发现流（DiscoverScreen 推荐 tab）的动态卡片 + 九宫格图。
# 如果它出错了：脚本报错退出，这批动态没入库；已入库的按作者幂等，--force 重灌。
#
# 用法（backend/ 下，库已 upgrade head）：
#   $env:PYTHONPATH='.'; D:/conda/python.exe -X utf8 curate_posts.py [--force]
# ============================================================
import io
import os
import sys
import urllib.request
from datetime import datetime, timedelta, timezone

from app.core.config import settings
from app.core.db import SessionLocal
from app.models import Post, PostMedia, User


def _http_get(url: str) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 kankan-curator"})
    with urllib.request.urlopen(req, timeout=25) as r:
        return r.read()


def _download_photo(idx: int, n: int, w: int = 600, h: int = 600) -> str:
    """从 Picsum 下载一张真实照片转存本地 uploads，返回 /uploads 相对路径。
    下载失败退回本地生成的纯色图（不至于让脚本挂）。"""
    os.makedirs(settings.upload_dir, exist_ok=True)
    fname = f"post_{idx}_{n}.jpg"
    path = os.path.join(settings.upload_dir, fname)
    try:
        data = _http_get(f"https://picsum.photos/seed/kkpost{idx}_{n}/{w}/{h}")
        if data and len(data) > 3000:
            with open(path, "wb") as f:
                f.write(data)
            return f"/uploads/{fname}"
    except Exception as e:
        print(f"  Picsum 下载失败 {idx}_{n}: {e}，用纯色兜底")
    try:
        from PIL import Image
        Image.new("RGB", (w, h), (0xC9, 0xD6, 0xC0)).save(path)
    except Exception:
        pass
    return f"/uploads/{fname}"


def _make_gif(idx: int) -> str:
    """PIL 本地生成一张循环动画 GIF（渐变底 + 环绕光点），真动图，离线可显。"""
    os.makedirs(settings.upload_dir, exist_ok=True)
    fname = f"post_{idx}_anim.gif"
    path = os.path.join(settings.upload_dir, fname)
    try:
        import math

        from PIL import Image, ImageDraw
    except Exception:
        return _download_photo(idx, 0)  # 无 PIL 退回照片
    W = H = 420
    top, bottom = (0x24, 0x2B, 0x3A), (0x3A, 0x6E, 0x5B)
    base = Image.new("RGB", (W, H))
    for y in range(H):
        t = y / (H - 1)
        base.putpixel((0, y), tuple(int(top[c] * (1 - t) + bottom[c] * t) for c in range(3)))
    base = base.resize((W, H))
    frames = []
    dots = [(0.0, (0x8F, 0xE3, 0xB0)), (2.1, (0xF0, 0xCE, 0x8A)), (4.2, (0xA9, 0xC7, 0xF0))]
    for f in range(24):
        img = base.copy()
        d = ImageDraw.Draw(img)
        ang0 = f / 24 * 2 * math.pi
        for phase, color in dots:
            a = ang0 + phase
            cx = W / 2 + math.cos(a) * 120
            cy = H / 2 + math.sin(a) * 120
            r = 26
            d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=color)
        frames.append(img)
    frames[0].save(path, save_all=True, append_images=frames[1:], duration=70, loop=0, optimize=True)
    return f"/uploads/{fname}"


# 正常名字的动态作者（表现像真实用户；与 image#5 参考里 阿May/林娜/老王 呼应）。
AUTHORS = {
    "amay": dict(email="amay@kankan.dev", nickname="阿May", bio="AI 绘画重度用户，爱折腾国风"),
    "linna": dict(email="linna@kankan.dev", nickname="林娜", bio="做视频的，最近迷上图生视频"),
    "laowang": dict(email="laowang@kankan.dev", nickname="老王", bio="独立开发，什么模型都想试试"),
    "chenyu": dict(email="chenyu@kankan.dev", nickname="陈屿", bio="AI 绘画 & 提示词爱好者"),
    "linan": dict(email="linan@kankan.dev", nickname="林岸", bio="做后端的，业余折腾本地大模型"),
}

# 每条动态：author / content / tags / media（类型 + 张数）。覆盖多种配图布局。
POSTS = [
    dict(
        author="amay",
        content="整理了这周用 Midjourney 出的一组国风插画，配色越练越顺手～九张放一起看更带感，提示词模板评论区发。",
        tags=["midjourney", "aigc", "国风"],
        media=("photos", 9, 600, 600),  # 九宫格
    ),
    dict(
        author="linna",
        content="用 Runway 把一张手绘草图直接变成了动态海报，第一次做就上头了。图生视频这条线真的香。",
        tags=["runway", "视频创作"],
        media=("photos", 1, 1000, 680),  # 单大图
    ),
    dict(
        author="laowang",
        content="同一句提示词分别喂给 SDXL / Flux / MJ 出图对比，三种风格差挺多，各有各的味道。",
        tags=["sdxl", "flux", "对比"],
        media=("photos", 3, 600, 600),  # 三图一排
    ),
    dict(
        author="amay",
        content="收藏夹里常开的四个 AI 工具，界面都挺顺手，截个图存档。",
        tags=["工具", "效率"],
        media=("photos", 4, 600, 600),  # 四图
    ),
    dict(
        author="chenyu",
        content="小发现：让 Claude 写正则表达式，直接用大白话描述需求就行，出来还自带注释，比我手写快多了。纯文字分享，无图。",
        tags=["claude", "效率"],
        media=None,  # 纯文字
    ),
    dict(
        author="linan",
        content="拿 AI 做了个循环动画当壁纸，分享个 demo，能一直看下去。",
        tags=["ai动画", "壁纸"],
        media=("gif",),  # GIF 动图
    ),
]


def get_or_create_author(db, key: str) -> User:
    spec = AUTHORS[key]
    user = db.query(User).filter(User.email == spec["email"]).one_or_none()
    if user is None:
        user = User(email=spec["email"], nickname=spec["nickname"], bio=spec["bio"],
                    interests=["design", "dev"], role="creator")
        db.add(user)
        db.flush()
        print(f"created author {spec['nickname']} {user.id}")
    return user


def main() -> None:
    force = "--force" in sys.argv
    db = SessionLocal()
    try:
        authors = {k: get_or_create_author(db, k) for k in AUTHORS}
        author_ids = [u.id for u in authors.values()]

        existing = db.query(Post).filter(Post.author_user_id.in_(author_ids)).all()
        if existing and not force:
            print(f"已有 {len(existing)} 条本批动态，跳过（加 --force 重灌）。")
            return
        if existing and force:
            for p in existing:
                db.delete(p)
            db.flush()
            print(f"--force：删除旧的本批动态 {len(existing)} 条")

        now = datetime.now(timezone.utc)
        media_total = 0
        for i, spec in enumerate(POSTS):
            author = authors[spec["author"]]
            post = Post(
                author_user_id=author.id,
                content=spec["content"],
                tags=spec["tags"],
                like_count=0,
                created_at=now - timedelta(minutes=i * 7),
            )
            db.add(post)
            db.flush()  # 拿 post.id 挂配图
            m = spec["media"]
            urls = []
            if m and m[0] == "photos":
                _, count, w, h = m
                urls = [(_download_photo(i, n, w, h), "image") for n in range(count)]
            elif m and m[0] == "gif":
                urls = [(_make_gif(i), "image")]  # GIF 以 image 存，前端会动
            for order, (url, mt) in enumerate(urls):
                db.add(PostMedia(post_id=post.id, media_type=mt, url=url, sort_order=order))
                media_total += 1
            print(f"  动态[{i}] {author.nickname}：{len(urls)} 图")
        db.commit()
        print(f"已灌入 {len(POSTS)} 条动态 + {media_total} 张配图。")
    finally:
        db.close()


if __name__ == "__main__":
    main()
