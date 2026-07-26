# ============================================================
# 给马甲号配头像。用户 2026-07-26：**不用真人脸**，用 卡通 / 风景 / 自然 / 艺术 / 猫 / 狗 /
#   剪影 / 抽象 等元素，从公开/开放授权图源抓（非商用产品，授权顾虑放宽）。
#
# 图源混搭（都免费/开放）：
#   猫 cataas.com · 狗 dog.ceo · 风景自然艺术 picsum.photos(源自 Unsplash) ·
#   插画/剪影/抽象 DiceBear(shapes/bottts/thumbs/icons/rings/glass/identicon)
# 按人设无关地打散分配（不是一屏全猫），种子稳定 → 同一马甲每次同一张。
# 抓取失败 → 回退本地渐变底 + 首字，绝不硬失败。转存进 upload_dir(/uploads)，上线走 OSS。
#
# 跑：python seed_avatars.py --all      # 给全部 200 马甲重刷非人脸头像（推荐）
#     python seed_avatars.py            # 只补没有头像的
#   仅处理马甲；真实用户头像不动（真人默认走前端首字母头像）。
# ============================================================
import hashlib
import os
import sys
import time

import httpx
from PIL import Image, ImageDraw, ImageFont

from app.core.config import settings
from app.core.db import SessionLocal
from app.services.personas import persona_users

# 每个马甲分到的「图源类别」——按序轮转打散，比例偏向稳定可复现的源。
_DICEBEAR_STYLES = ["shapes", "bottts", "thumbs", "icons", "rings", "glass", "identicon", "fun-emoji"]
_CATEGORIES = (
    ["picsum"] * 5 +     # 风景/自然/艺术（真实照片，seed 稳定）
    ["dicebear"] * 5 +   # 插画/剪影/抽象
    ["cat"] * 3 +        # 猫
    ["dog"] * 3          # 狗
)  # 16 一轮，200 个 → 均匀混搭


def _get(url: str, path: str, follow=True) -> bool:
    try:
        r = httpx.get(url, timeout=20, trust_env=False, follow_redirects=follow,
                      headers={"User-Agent": "kankan-seed/1.0"})
        if r.status_code == 200 and r.headers.get("content-type", "").startswith("image"):
            with open(path, "wb") as f:
                f.write(r.content)
            return True
    except Exception as exc:
        print(f"  抓取失败 {url[:60]}: {exc}")
    return False


def fetch_avatar(category: str, seed: str, path: str) -> bool:
    """按类别抓一张头像到 path。返回是否成功。"""
    if category == "picsum":
        return _get(f"https://picsum.photos/seed/{seed}/256/256", path)
    if category == "dicebear":
        style = _DICEBEAR_STYLES[int(hashlib.md5(seed.encode()).hexdigest(), 16) % len(_DICEBEAR_STYLES)]
        return _get(f"https://api.dicebear.com/9.x/{style}/png?seed={seed}&size=256&radius=50", path)
    if category == "cat":
        return _get(f"https://cataas.com/cat?width=256&height=256&_={seed}", path)
    if category == "dog":
        try:
            j = httpx.get("https://dog.ceo/api/breeds/image/random", timeout=20,
                          trust_env=False, headers={"User-Agent": "kankan-seed/1.0"}).json()
            if j.get("status") == "success" and j.get("message"):
                return _get(j["message"], path)
        except Exception as exc:
            print(f"  狗 API 失败: {exc}")
    return False


# —— 回退：本地渐变底 + 首字（离线兜底，与旧实现一致）——
_GRADIENTS = [
    ((0xF6, 0x8B, 0x5C), (0xD8, 0x5A, 0x30)), ((0x3F, 0xC1, 0x8F), (0x1D, 0x9E, 0x75)),
    ((0x5B, 0x8D, 0xEF), (0x34, 0x5C, 0xBE)), ((0xB9, 0x8A, 0xE8), (0x7B, 0x58, 0xB0)),
    ((0xF2, 0xB5, 0x4C), (0xC9, 0x88, 0x1E)), ((0xEC, 0x6F, 0x8E), (0xC7, 0x43, 0x67)),
    ((0x4F, 0xC4, 0xC4), (0x2A, 0x93, 0x9A)), ((0x8C, 0xB3, 0x69), (0x5E, 0x8A, 0x3C)),
]
_FONT_CANDIDATES = (
    r"C:\Windows\Fonts\msyh.ttc", r"C:\Windows\Fonts\simhei.ttf",
    "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
    "/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc",
    "/System/Library/Fonts/PingFang.ttc", r"C:\Windows\Fonts\arial.ttf",
)


def _font(size: int):
    for fp in _FONT_CANDIDATES:
        if os.path.exists(fp):
            try:
                return ImageFont.truetype(fp, size)
            except OSError:
                continue
    return ImageFont.load_default()


def _make_gradient_avatar(glyph: str, c0, c1, path: str) -> None:
    size = 256
    base = Image.new("RGB", (size, size))
    px = base.load()
    for y in range(size):
        for x in range(size):
            t = (x + y) / (2 * (size - 1))
            px[x, y] = (int(c0[0] + (c1[0] - c0[0]) * t),
                        int(c0[1] + (c1[1] - c0[1]) * t),
                        int(c0[2] + (c1[2] - c0[2]) * t))
    draw = ImageDraw.Draw(base)
    font = _font(130)
    box = draw.textbbox((0, 0), glyph, font=font)
    w, h = box[2] - box[0], box[3] - box[1]
    draw.text(((size - w) / 2 - box[0], (size - h) / 2 - box[1]), glyph, fill=(255, 255, 255), font=font)
    base.save(path)


def main() -> None:
    all_users = "--all" in sys.argv
    os.makedirs(settings.upload_dir, exist_ok=True)
    db = SessionLocal()
    ok = fallback = 0
    try:
        personas = sorted(persona_users(db), key=lambda u: u.email or "")
        for idx, u in enumerate(personas):
            if not all_users and u.avatar_url:
                continue
            seed = (u.email or str(u.id)).split("@")[0]
            category = _CATEGORIES[idx % len(_CATEGORIES)]
            fname = f"avatar_{str(u.id).replace('-', '')[:8]}.png"
            path = os.path.join(settings.upload_dir, fname)
            if fetch_avatar(category, seed, path):
                ok += 1
            else:
                gi = int(hashlib.md5((u.nickname or str(u.id)).encode("utf-8")).hexdigest(), 16) % len(_GRADIENTS)
                c0, c1 = _GRADIENTS[gi]
                _make_gradient_avatar((u.nickname or "看")[0], c0, c1, path)
                fallback += 1
            u.avatar_url = f"/uploads/{fname}"
            if idx % 20 == 0:
                db.commit()
                print(f"  ...{idx + 1}/{len(personas)}（{category}）")
            time.sleep(0.15)  # 礼貌节流，别把免费 API 打崩
        db.commit()
        print(f"头像：抓取成功 {ok}，离线回退渐变 {fallback}（共 {len(personas)} 马甲，"
              f"{'全部重刷' if all_users else '仅补空缺'}）")
    finally:
        db.close()


if __name__ == "__main__":
    main()
