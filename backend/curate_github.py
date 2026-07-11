# ============================================================
# 这个文件是干什么的：Track B「Agent-bootstrap」的第一批产物——把 agent（本 CLI）
#   精选 + 加厚过的真实 GitHub AI 项目，作为已发布 Project 灌进库里，验证富字段结构与内容质量。
# 它对应产品里的什么功能：发现流/看看里出现有血有肉的真实内容（非 lorem 占位），
#   带原作者归属（source_url / original_author_*）、内容类型（content_type）、AI 实现线索。
# 如果它出错了：脚本报错退出，这批内容没入库；已入库的按 source_url 幂等，重跑不会重复。
#
# 用法（在 backend/ 下，先起好库并 alembic upgrade head）：
#   $env:PYTHONPATH='.'; D:/conda/python.exe -X utf8 curate_github.py
#   加 --force 会先按 source_url 删掉旧的这批再重灌（幂等）。
#
# 注意：这是「先 agent 验证质量」的手工 bootstrap（见 PIPELINE_PLAN.md 四/五）。
#   内容由 agent 读真实 GitHub 仓库信息后中文本地化改写而成——风格像、内容原创、带出处，不搬运。
# ============================================================
import os
import sys
from datetime import datetime, timedelta, timezone

from app.core.config import settings
from app.core.db import SessionLocal
from app.models import Project, User

# 封面配色（柔和双色渐变），给无外网环境（模拟器）也能显示封面。
_COVER_GRADIENTS = [
    ((0xEC, 0xEF, 0xF5), (0x8C, 0xA6, 0xD6)),  # 冷蓝 · ComfyUI
    ((0xEA, 0xF4, 0xEE), (0x6F, 0xB8, 0x94)),  # 薄荷 · Ollama
    ((0xF0, 0xEC, 0xF4), (0xA0, 0x86, 0xC9)),  # 薰衣草 · Dify
    ((0xF5, 0xEE, 0xE2), (0xD1, 0xA6, 0x6E)),  # 暖沙 · prompts.chat
]


def _ensure_cover(idx: int) -> str:
    """本地生成 800x600 双色竖向渐变封面，存进 upload_dir，返回 /uploads 相对路径。
    PIL 不可用时退回一张纯占位路径（不至于让脚本挂掉）。"""
    try:
        from PIL import Image
    except Exception:
        return f"/uploads/curate_cover_{idx}.png"
    os.makedirs(settings.upload_dir, exist_ok=True)
    fname = f"curate_cover_{idx}.png"
    path = os.path.join(settings.upload_dir, fname)
    top, bottom = _COVER_GRADIENTS[idx % len(_COVER_GRADIENTS)]
    grad = Image.new("RGB", (1, 600))
    for y in range(600):
        t = y / 599
        grad.putpixel((0, y), tuple(int(top[c] * (1 - t) + bottom[c] * t) for c in range(3)))
    grad.resize((800, 600)).save(path)
    return f"/uploads/{fname}"


# 几个「正常名字」的编辑号（表现像真实用户，冷启动常见做法；见 PIPELINE_PLAN.md 决策 5）。
EDITORS = {
    "chenyu": dict(email="chenyu@kankan.dev", nickname="陈屿",
                   bio="AI 绘画 & 提示词爱好者，帮你把好东西翻成人话"),
    "linan": dict(email="linan@kankan.dev", nickname="林岸",
                  bio="做后端的，业余折腾本地大模型和 AI 应用"),
}


# 每条 = agent 读真实 GitHub 仓库后中文本地化加厚的富内容。
# 字段：editor 谁发 / content_type 成果类型 / category 用途 / domains 职业 / 原作者归属。
CURATED = [
    dict(
        editor="chenyu",
        title="ComfyUI：用连线搭出你的 AI 出图流水线",
        tagline="把 Stable Diffusion / Flux 拆成一个个节点，像搭积木一样组合，本地就能跑",
        summary=(
            "面向设计师与 AI 绘画玩家：ComfyUI 用节点图把扩散模型的每一步——加载模型、写提示词、"
            "采样、放大、局部重绘——都变成可连线的模块。相比一键式工具，它把控制权完全交给你，"
            "复杂工作流能存成文件反复复用，低显存的卡也能跑。"
        ),
        intro=(
            "## 它解决什么\n"
            "一般的出图工具是「填个提示词点生成」，好上手但一旦想精细控制就没辙。ComfyUI 反过来："
            "把出图的每一步都摊开成节点，你自己连线决定数据怎么流。想加 ControlNet 控构图、插 LoRA 换画风、"
            "接放大节点做高清修复，都是拖一个节点连根线的事。\n\n"
            "## 亮点\n"
            "- **节点式工作流**：一张图怎么来的完全透明，可保存、可分享、可复现\n"
            "- **模型覆盖广**：SD 1.5 / SDXL / Flux，甚至视频（LTX-Video）、3D 都能接\n"
            "- **省显存**：自动把模型在显存/内存间搬运，6G 小显存也能跑\n"
            "- **全平台**：N卡 / A卡 / Intel / Apple Silicon 都支持，还有桌面版和 API\n\n"
            "## 适合谁\n"
            "想深度控制出图效果的设计师、需要把出图接进自己流程的开发者、爱折腾工作流的 AI 绘画玩家。"
        ),
        ai_implementation_hint=(
            "核心是把扩散采样管线显式化：CLIP 文本编码 → KSampler 迭代去噪 → VAE 解码，"
            "中间可插 ControlNet / LoRA / 放大节点。想复刻先从官方默认工作流改起，再逐个加节点看效果。"
        ),
        content_type="tool", category="image_design",
        domains=["design", "video"],
        tools=["ComfyUI", "Stable Diffusion", "Flux", "ControlNet"],
        ai_badge="staff_pick", repo_stars="120k",
        source_url="https://github.com/comfyanonymous/ComfyUI",
        original_author_name="Comfy-Org",
        original_author_url="https://github.com/Comfy-Org",
    ),
    dict(
        editor="linan",
        title="Ollama：一行命令在本地跑大模型",
        tagline="ollama run 就能把 Llama、DeepSeek、Qwen 拉到自己电脑上聊，数据不出本机",
        summary=(
            "面向开发者与隐私敏感场景：Ollama 把开源大模型的下载、量化、运行、API 服务全打包成一个命令行工具。"
            "`ollama run qwen` 即可对话，还提供 REST API 和 Python/JS SDK，方便接进自己的应用，"
            "macOS/Windows/Linux/Docker 全平台。"
        ),
        intro=(
            "## 它解决什么\n"
            "以前想在本地跑开源大模型，得自己折腾权重下载、量化格式、推理后端一堆环境。Ollama 把这些全抹平："
            "装好后一句 `ollama run deepseek-r1` 就开始对话，模型自动下好，数据全程留在你机器上。\n\n"
            "## 亮点\n"
            "- **一句话起模型**：`ollama run <模型名>`，不碰环境配置\n"
            "- **模型库大**：Llama、DeepSeek、Qwen、Gemma、Mistral 等主流开源模型即拉即用\n"
            "- **自带 REST API**：`localhost:11434`，配 Python / JS SDK，几行代码接进应用\n"
            "- **数据不出本机**：适合隐私敏感、离线、内网场景\n\n"
            "## 适合谁\n"
            "想在本地/内网跑模型的开发者、做隐私敏感应用的团队、想省 API 费用做原型的人。"
        ),
        ai_implementation_hint=(
            "本质是给 llama.cpp 等推理后端套了一层模型管理 + REST API。接自己的应用走 "
            "http://localhost:11434/api/chat，换模型只改 model 名；显存紧张就用量化版（如 :7b-q4）。"
        ),
        content_type="opensource", category="automation_tools",
        domains=["dev"],
        tools=["Ollama", "Llama", "DeepSeek", "Qwen"],
        ai_badge="high_potential", repo_stars="176k",
        source_url="https://github.com/ollama/ollama",
        original_author_name="Ollama",
        original_author_url="https://github.com/ollama",
    ),
    dict(
        editor="linan",
        title="Dify：拖拽式搭建你自己的 AI 应用",
        tagline="可视化画布把 RAG、Agent、工作流连起来，从原型到上线一个平台搞定",
        summary=(
            "面向想做 AI 产品但不想从零写编排的团队：Dify 用可视化画布把大模型、知识库（RAG）、"
            "工具调用、Agent 串成工作流，几百种模型即插即用，自带可观测与运维面板，"
            "每个应用都配套 API 可嵌进自己的业务。"
        ),
        intro=(
            "## 它解决什么\n"
            "自己用代码把「提示词 + 检索 + 工具调用」拼成一个像样的 AI 应用，写起来又碎又难维护。"
            "Dify 把这些抽成画布上的节点，拖拽连线就能搭出 RAG 问答、Agent、多步工作流，还带上线后的观测。\n\n"
            "## 亮点\n"
            "- **可视化编排**：画布上连节点，复杂工作流看得见、改得动\n"
            "- **RAG 开箱即用**：文档入库→切分→向量检索→拼上下文，支持 PDF/PPT 等\n"
            "- **Agent 框架**：基于 Function Calling / ReAct，内置 50+ 工具\n"
            "- **模型即插即用 + 可观测**：几百种模型随便切，接 Langfuse 等看调用链\n"
            "- **一切皆 API**：搭好的应用直接给 API，嵌进自己的业务逻辑\n\n"
            "## 适合谁\n"
            "想快速做出 AI 应用原型并上线的团队、需要 RAG/Agent 但不想造轮子的开发者。"
        ),
        ai_implementation_hint=(
            "把「提示词 + 检索 + 工具调用」从代码里抽出来变成画布节点：文档入库→向量检索→"
            "拼进上下文→LLM→（可选）Agent 工具循环。先用模板起一个 RAG 问答，再往工作流加节点。"
        ),
        content_type="app", category="ai_apps",
        domains=["dev", "office"],
        tools=["Dify", "RAG", "Agent"],
        ai_badge="staff_pick", repo_stars="148k",
        source_url="https://github.com/langgenius/dify",
        original_author_name="LangGenius",
        original_author_url="https://github.com/langgenius",
    ),
    dict(
        editor="chenyu",
        title="prompts.chat：社区精选的上千条提示词库",
        tagline="从「扮演 Linux 终端」到「当我的英语老师」，复制即用的提示词合集",
        summary=(
            "面向所有 AI 使用者：这是全网最火的提示词合集之一（前身 awesome-chatgpt-prompts），"
            "把「让 AI 扮演某个角色/专家」的提示词按场景整理好，复制粘贴即可用。"
            "现已做成可自托管的开源站点，团队可私有部署保数据。"
        ),
        intro=(
            "## 它解决什么\n"
            "很多人用 AI 只会「你帮我写个…」，效果平平。真正拉开差距的是提示词——先给模型一个清晰身份和约束，"
            "它就专业很多。这个库把上千条这样的「角色扮演」提示词按场景整理好，拿来即用。\n\n"
            "## 亮点\n"
            "- **上千条精选**：面试官、翻译、英语老师、Linux 终端、产品经理……场景齐全\n"
            "- **复制即用**：每条都是打磨过的完整提示词，粘进 ChatGPT/Claude 就能用\n"
            "- **社区共建**：持续有人贡献新提示词，质量在筛\n"
            "- **可自托管**：开源站点，团队能私有部署，提示词不外流\n\n"
            "## 适合谁\n"
            "刚上手想快速见效的 AI 新人、想把提示词沉淀成团队资产的运营/产品。"
        ),
        ai_implementation_hint=(
            "套路是「角色设定 + 任务约束 + 输出格式」三段式：先给模型一个明确身份（「你是一位资深…」），"
            "再限定它只做某件事、按某种格式回答。照着库里模板改成自己的场景最快。"
        ),
        content_type="prompt", category="work_efficiency",
        domains=["writing", "office"],
        tools=["ChatGPT", "Claude"],
        ai_badge="high_potential", repo_stars="165k",
        source_url="https://github.com/f/awesome-chatgpt-prompts",
        original_author_name="Fatih Kadir Akın",
        original_author_url="https://github.com/f",
    ),
]


def get_or_create_editor(db, key: str) -> User:
    spec = EDITORS[key]
    user = db.query(User).filter(User.email == spec["email"]).one_or_none()
    if user is None:
        user = User(
            email=spec["email"],
            nickname=spec["nickname"],
            bio=spec["bio"],
            interests=["dev", "design"],
            role="creator",
        )
        db.add(user)
        db.flush()
        print(f"created editor {spec['nickname']} {user.id}")
    else:
        print(f"editor exists {spec['nickname']} {user.id}")
    return user


def main() -> None:
    force = "--force" in sys.argv
    db = SessionLocal()
    try:
        editors = {key: get_or_create_editor(db, key) for key in EDITORS}

        source_urls = [c["source_url"] for c in CURATED]
        existing = db.query(Project).filter(Project.source_url.in_(source_urls)).all()
        if existing and not force:
            print(f"已有 {len(existing)} 条本批内容，跳过（加 --force 重灌）。")
            return
        if existing and force:
            for p in existing:
                db.delete(p)
            db.flush()
            print(f"--force：删除旧的本批内容 {len(existing)} 条")

        now = datetime.now(timezone.utc)
        for i, c in enumerate(CURATED):
            author = editors[c["editor"]]
            db.add(
                Project(
                    author_user_id=author.id,
                    title=c["title"],
                    tagline=c["tagline"],
                    summary=c["summary"],
                    intro=c["intro"],
                    ai_implementation_hint=c["ai_implementation_hint"],
                    category=c["category"],
                    content_type=c["content_type"],
                    language="zh-CN",
                    # 手动导入（agent 精选）+ 非站内原创 + GitHub 原作者归属
                    source_type="manual_import",
                    is_original=False,
                    source_platform="github",
                    source_url=c["source_url"],
                    original_author_name=c["original_author_name"],
                    original_author_url=c["original_author_url"],
                    domains=c["domains"],
                    tools=c["tools"],
                    ai_badge=c["ai_badge"],
                    cover_media_url=_ensure_cover(i),
                    repo_stars=c["repo_stars"],
                    allow_how_to_interest=True,
                    status="published",
                    hot_score=float(95 - i * 6),
                    published_at=now - timedelta(minutes=i),
                )
            )
        db.commit()
        print(f"已灌入 {len(CURATED)} 条精选 GitHub 项目（编辑号：{', '.join(e['nickname'] for e in EDITORS.values())}）")
    finally:
        db.close()


if __name__ == "__main__":
    main()
