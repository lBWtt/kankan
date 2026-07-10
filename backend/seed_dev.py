# ============================================================
# 这个文件是干什么的：开发环境种子脚本——往空库里灌一个种子用户 + 若干条已发布项目，
#   让前端"看看/发现流"接上后端后能立刻看到真实数据。
# 它对应产品里的什么功能：本地联调（GET /projects 有货可刷）。
# 如果它出错了：脚本报错退出，库里没数据，前端列表为空。
#
# 用法（在 backend/ 下，先起好库并 alembic upgrade head）：
#   $env:PYTHONPATH='.'; .venv\Scripts\python.exe -X utf8 seed_dev.py
#   加 --force 会先清掉之前种下的种子项目再重灌（幂等）。
# ============================================================
import os
import sys
from datetime import datetime, timedelta, timezone

from app.core.config import settings
from app.core.db import SessionLocal
from app.models import Project, User

# 种子封面配色（柔和双色渐变，暖纸/薄荷调，6 张各不同）。
_COVER_GRADIENTS = [
    ((0xEA, 0xF4, 0xEE), (0x8F, 0xC9, 0xA9)),  # mint
    ((0xF5, 0xEE, 0xE2), (0xD9, 0xB8, 0x8C)),  # sand
    ((0xEC, 0xEF, 0xF5), (0x9F, 0xB4, 0xD6)),  # slate blue
    ((0xF4, 0xEA, 0xEC), (0xCE, 0x9A, 0xA6)),  # dusty rose
    ((0xEE, 0xF1, 0xE8), (0xA9, 0xC0, 0x86)),  # olive
    ((0xF0, 0xEC, 0xF4), (0xB0, 0x9C, 0xC9)),  # lavender
]


def _ensure_cover(idx: int, fallback: str) -> str:
    """开发种子封面：本地生成一张 800x600 双色渐变图存进 upload_dir，返回 /uploads 相对路径。
    这样模拟器/无外网环境也能显示封面（原来用外网 picsum，断网时破图）。
    PIL 不可用时退回原外链 URL（fallback），保证脚本在任何环境都能跑。"""
    try:
        from PIL import Image
    except Exception:
        return fallback
    os.makedirs(settings.upload_dir, exist_ok=True)
    fname = f"seed_cover_{idx}.png"
    path = os.path.join(settings.upload_dir, fname)
    top, bottom = _COVER_GRADIENTS[idx % len(_COVER_GRADIENTS)]
    # 1×600 竖向渐变列，再横向拉伸到 800 宽（快且干净）。
    grad = Image.new("RGB", (1, 600))
    for y in range(600):
        t = y / 599
        grad.putpixel((0, y), tuple(int(top[c] * (1 - t) + bottom[c] * t) for c in range(3)))
    grad.resize((800, 600)).save(path)
    return f"/uploads/{fname}"

SEED_EMAIL = "seed@kankan.dev"

# (title, tagline, summary, category, domains, tools, ai_badge, cover, repo_stars, takeaways)
SEED_PROJECTS = [
    (
        "用 Midjourney 做国风电商主图",
        "一句提示词批量出图，转化率提了三成",
        "面向电商设计师：用结构化提示词 + 局部重绘，把商品图做成有质感的国风海报，附完整提示词模板与参数。",
        "image_design", ["design", "ecommerce"], ["Midjourney", "Photoshop"],
        "staff_pick", "https://picsum.photos/seed/kk1/800/600", "—", 128,
    ),
    (
        "Claude 写周报：把 git log 变成人话",
        "每周省半小时，老板还看得懂",
        "开发者向：用一段 prompt 把一周 commit 记录整理成结构化周报，含要点、风险、下周计划，可直接贴进钉钉。",
        "work_efficiency", ["dev", "office"], ["Claude", "Git"],
        "high_potential", "https://picsum.photos/seed/kk2/800/600", "—", 342,
    ),
    (
        "Runway 把分镜草图变短视频",
        "自媒体人的一人剧组",
        "视频创作者向：手绘分镜 → 图生视频 → 剪辑拼接的完整工作流，含镜头提示词与转场技巧。",
        "video_music", ["video", "marketing"], ["Runway", "CapCut"],
        "worth_a_look", "https://picsum.photos/seed/kk3/800/600", "—", 89,
    ),
    (
        "一个提示词生成落地页文案",
        "冷启动阶段的省钱利器",
        "营销/运营向：输入产品一句话，输出 H1、卖点、CTA 三段式落地页文案，附 A/B 两版语气。",
        "business_ideas", ["marketing", "writing"], ["ChatGPT"],
        "none", "https://picsum.photos/seed/kk4/800/600", "—", 56,
    ),
    (
        "开源：本地跑的 AI 会议纪要工具",
        "录音进去，纪要出来，数据不出本机",
        "开发者向：Whisper 转写 + 本地 LLM 摘要的桌面小工具，隐私友好，附一键部署脚本。",
        "automation_tools", ["dev"], ["Whisper", "Ollama"],
        "high_potential", "https://picsum.photos/seed/kk5/800/600", "2.3k", 210,
    ),
    (
        "给老师做的 AI 出题助手",
        "按知识点自动出卷 + 答案解析",
        "教育向：输入章节与难度，生成选择/填空/简答题与详细解析，支持导出 Word。",
        "learning_growth", ["education", "office"], ["Claude", "Word"],
        "worth_a_look", "https://picsum.photos/seed/kk6/800/600", "—", 74,
    ),
]


def get_or_create_seed_user(db) -> User:
    user = db.query(User).filter(User.email == SEED_EMAIL).one_or_none()
    if user is None:
        user = User(
            email=SEED_EMAIL,
            nickname="看看小编",
            bio="种子内容作者（开发环境）",
            interests=["design", "dev"],
            role="creator",
        )
        db.add(user)
        db.flush()
        print(f"created seed user {user.id}")
    else:
        print(f"seed user exists {user.id}")
    return user


def main() -> None:
    force = "--force" in sys.argv
    db = SessionLocal()
    try:
        user = get_or_create_seed_user(db)

        existing = db.query(Project).filter(Project.author_user_id == user.id).all()
        if existing and not force:
            print(f"已有 {len(existing)} 条种子项目，跳过（加 --force 重灌）。")
            return
        if existing and force:
            for p in existing:
                db.delete(p)
            db.flush()
            print(f"--force：删除旧种子项目 {len(existing)} 条")

        now = datetime.now(timezone.utc)
        for i, (title, tagline, summary, category, domains, tools, badge, cover, stars, takeaways) in enumerate(
            SEED_PROJECTS
        ):
            db.add(
                Project(
                    author_user_id=user.id,
                    title=title,
                    tagline=tagline,
                    summary=summary,
                    category=category,
                    language="zh-CN",
                    source_type="user_original",
                    is_original=True,
                    domains=domains,
                    tools=tools,
                    ai_badge=badge,
                    # 本地生成封面（/uploads/…），无外网也能显示；PIL 缺失时退回原 cover 外链。
                    cover_media_url=_ensure_cover(i, cover),
                    repo_stars=stars,
                    takeaway_count=takeaways,
                    allow_how_to_interest=True,
                    status="published",
                    # hot_score 递减、published_at 错开，保证列表有稳定顺序（新→旧）
                    hot_score=float(100 - i * 7),
                    published_at=now - timedelta(minutes=i),
                )
            )
        db.commit()
        print(f"已种下 {len(SEED_PROJECTS)} 条已发布项目，作者 = {user.nickname}")
    finally:
        db.close()


if __name__ == "__main__":
    main()
