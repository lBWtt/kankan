# ============================================================
# 这个文件是干什么的：AI 抓取管线的"整理车间"——把候选池里刚抓回来的原料（ai_collected）
#   交给 Claude 整理成结构化字段：中文标题/亮点/简介、分类/领域/工具/标签、实现思路、
#   编辑分、风险标记，整理完推进到待审核（pending_review）。
# 它对应产品里的什么功能：PRD §10"AI 初步整理"；后台审核员看到的候选字段全部产自这里。
# 如果它出错了，用户会看到什么现象：候选池堆积原料无人整理，审核没东西可审，App 新内容停更；
#   或整理质量差（幻觉实现思路、错分类）加重审核负担。
# ============================================================
import json
import logging
import re
from pathlib import Path
from typing import Callable, Dict, List, Literal, Optional

from pydantic import BaseModel, Field, field_validator
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.errors import AppError
from app.models import CandidateContent
from app.models.enums import CATEGORY, DOMAIN
from app.services import ai_budget
from app.services.candidates import check_post_gate, check_publish_gate, select_proof_media

logger = logging.getLogger("app.ai_processor")

# 风险标记的固定取值（admin 文档 §4：疑似广告/重复/侵权/低质，AI 标了运营必须人工确认）
RISK_FLAGS = ("suspected_ad", "duplicate", "copyright_risk", "low_quality")

# 内容宪法 v1.1：吸引力五维。总分只在后端计算，模型不得自报 composite。
POLICY_VERSION = "1.1"
SCORE_WEIGHTS = {
    "hook_clarity": 0.25,
    "visual_impact": 0.25,
    "surprise": 0.20,
    "tryability": 0.15,
    "shareability": 0.15,
}
WORK_FORMS = ("app", "website", "workflow", "model", "prompt", "ai_art", "game", "tool")
EXPERIENCE_TYPES = ("web", "video", "gallery", "download", "model_page", "workflow_file", "prompt_content", "game")


class AnalysisScores(BaseModel):
    """五个维度各 0-100；加权合成在 Python 里算，不让模型做算术。"""
    hook_clarity: int = Field(ge=0, le=100, description="只看标题和封面，五秒能否明白效果")
    visual_impact: int = Field(ge=0, le=100, description="成果图、前后对比或演示是否有冲击力")
    surprise: int = Field(ge=0, le=100, description="是否让人产生居然还能这样的感觉")
    tryability: int = Field(ge=0, le=100, description="能否立即观看、试玩、使用或复用")
    shareability: int = Field(ge=0, le=100, description="是否值得转给朋友或发群")


class CandidateAnalysis(BaseModel):
    """AI 整理的全部产出（结构化输出 schema；中文面向用户，枚举值面向系统）。"""
    is_work: bool = Field(description="完整作品=True；通用库/框架/SDK/引擎/数据集/协议/脚手架=False")
    work_rejection_reason: Optional[str] = Field(default=None, description="is_work=False 时说明为什么只是原料")
    work_form: Literal[WORK_FORMS]  # type: ignore[valid-type]
    creator_type: Literal["indie", "company"]
    access_friction: Literal["instant", "install", "technical"]
    title_candidates: List[str] = Field(
        min_length=2, max_length=2,
        description="两个不同角度的结果导向中文标题；每个 12-28 个可见字符",
    )
    hook_sentence: str = Field(min_length=5, max_length=140, description="一句话说明为什么值得看")
    summary: str = Field(min_length=20, max_length=500, description="中文简介，直接介绍项目本身、有网感不堆术语，**别提谁做的/来源平台**，别以「X 是一个」开头，别用「我做了」冒充")
    description: Optional[str] = Field(default=None, description="一段直接介绍这个项目的话：它是什么、能干嘛、怎么用、亮点/注意点。**别提是谁做的、别提来源平台、别说「有人做了/一位用户/转发」**，也别用「我做了/我试了」冒充。有网感、口语（可借鉴动态口吻），但要把项目要点（能干嘛/怎么用/好在哪）讲清楚，别机械说明书、别以「这是一个/X 是一个」开头。**字数多就分 2~3 小段、段间空一行。** 3-6 句，只依据原文不编造，实在没料才留空。")
    category: Literal[CATEGORY] = Field(description="一级分类，必选一个")  # type: ignore[valid-type]
    domains: List[Literal[DOMAIN]] = Field(min_length=1, description="相关职业领域，至少 1 个，宁准勿多")  # type: ignore[valid-type]
    tools: List[str] = Field(default_factory=list, description="用到的 AI 工具/模型名，原文有提才填，不猜")
    tags: List[str] = Field(min_length=1, description="自由标签 1-5 个，中文，方便检索")
    target_users: List[str] = Field(default_factory=list, description="适合人群，如'自媒体作者'")
    use_cases: List[str] = Field(default_factory=list, description="使用场景，如'批量生成商品图'")
    implementation_steps: Optional[List[str]] = Field(
        default=None, max_length=3,
        description="AI 推测的实现思路，每步一句话、最多 3 步。只在来源/工具清晰、思路可信时填；没把握就 null，宁缺勿错",
    )
    scores: AnalysisScores
    value_score: int = Field(ge=0, le=100, description="实用价值；不参与 attraction 总分")
    risk_flags: List[Literal[RISK_FLAGS]] = Field(  # type: ignore[valid-type]
        default_factory=list, description="风险标记：suspected_ad 疑似广告 / duplicate 疑似重复 / copyright_risk 疑似侵权 / low_quality 低质"
    )
    risk_note: Optional[str] = Field(default=None, description="标了风险时一句话说明原因")
    why_recommend: Optional[str] = Field(default=None, description="给运营看的一句话推荐理由")
    experience_type: Literal[EXPERIENCE_TYPES]  # type: ignore[valid-type]
    experience_url: Optional[str] = Field(default=None, description="web/video/model_page/game 等有链接时填；不编造")
    experience_content: Optional[str] = Field(default=None, max_length=12000, description="提示词正文或工作流等无独立 URL 的可复用内容")
    selected_proof_media_index: Optional[int] = Field(default=None, ge=0, description="从输入媒体清单选成果证据；没有可信证据则 null")

    @field_validator("title_candidates")
    @classmethod
    def _validate_title_candidates(cls, value: List[str]) -> List[str]:
        cleaned = [title.strip() for title in value]
        if len(set(cleaned)) != 2:
            raise ValueError("两个标题候选必须不同")
        if any(not 12 <= len(title) <= 28 for title in cleaned):
            raise ValueError("每个标题候选必须为 12～28 个可见字符")
        return cleaned


class PostAnalysis(BaseModel):
    """动态（post/动态）富化产出：把抓来的 AI 资讯/即刻讨论改写成一条像真人发的动态。
    只要正文 + 话题标签，不要项目那套结构化字段。"""
    content: str = Field(min_length=8, max_length=260,
                         description="轻改后的动态正文。**跟原帖一样短**——一两句为主、最多三四行；保住原帖的语气和网感，别扩写、别解释、别写成段落/报告")
    tags: List[str] = Field(min_length=1, max_length=5, description="话题标签 1-5 个，中文，不带 # 号")
    risk_flags: List[Literal[RISK_FLAGS]] = Field(  # type: ignore[valid-type]
        default_factory=list, description="风险标记：suspected_ad/duplicate/copyright_risk/low_quality")
    risk_note: Optional[str] = Field(default=None, description="标了风险时一句话说明")


# 整理函数的形状：拿候选原料 dict，返回 CandidateAnalysis / PostAnalysis。
# 真实实现是 claude_analyze；冒烟测试注入假实现，不花 API 钱。
AnalyzeFn = Callable[[dict], CandidateAnalysis]
PostAnalyzeFn = Callable[[dict], PostAnalysis]

# 「口吻库」：即刻 AI 圈里几种典型真人腔调。每条内容**随机换一种**，避免全是一个
# 说明文腔、一看就是批量生成。用户诉求：别光学一个人，换不同人的口吻发。
# 注意：只改「怎么说」（tagline/summary/description、动态 content），不改事实与结构化字段。
CONTENT_VOICES = [
    "安利体：像刚发现好东西迫不及待安利给朋友，兴奋直接，'最近在用的这个真的可以'那种，口语、带点私人感受。",
    "踩坑体：第一人称讲自己折腾的经历，有过程有槽点，'折腾了半天才搞明白''一开始被劝退，后来发现'这种真实感。",
    "冷静测评体：理性、克制，像认真用过一段时间后给结论，点出它强在哪、什么人用得上、有什么不足，不吹。",
    "技术宅体：关注它怎么做到的，提一嘴用了什么、思路巧在哪，稍微专业但不掉书袋、不堆术语。",
    "数字游民体：从一个人单干/自由职业的视角看'这东西能帮我省什么事'，实用、接地气。",
    "好奇尝鲜体：'刷到个有意思的东西'的分享发现感，轻快、带好奇，不急着下结论。",
    "毒舌但真诚体：先吐槽再真香，'本来不看好，结果'，有态度、有反转，不做作。",
]

# 项目文案「写作角度」库：让不同项目读起来像不同的人写的（用户反馈：项目都一个模板腔）。
# 关键——只换**切入点/结构/语气**，仍是客观第三方介绍：不破 rule 8（禁第一人称冒充作者、禁提来源平台）。
PROJECT_ANGLES = [
    "亮点先行：开头先甩最抓人的一个点/效果/数字，再补它是什么、怎么用。",
    "场景切入：从一个具体使用场景或痛点开场，再讲这东西怎么解决。",
    "冷静测评：像认真用过一阵后给结论——强在哪、适合谁、有什么局限，不吹。",
    "发现感：带点『刷到个有意思的东西』的轻快好奇，别急着下结论。",
    "技术视角：关注它怎么做到的、巧在哪，稍专业但不堆术语。",
    "实用主义：直接讲它能帮你省什么事、怎么快速上手，接地气。",
    "反差开场：先点一个反常识或让人意外的地方，再展开。",
]


def _pick_angle() -> str:
    import random
    return random.choice(PROJECT_ANGLES)


def _load_jike_voice_samples() -> List[str]:
    """加载从即刻真实抓来的口吻样本（scrape/jike_voice_samples.json）。
    用户要求：对照即刻真人的口吻，不是自己编。有真样本就用真样本，没有才退回内置档位。"""
    import os
    path = os.path.join(os.path.dirname(__file__), "..", "..", "scrape", "jike_voice_samples.json")
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        return [s["text"] for s in data if isinstance(s, dict) and s.get("text")]
    except Exception:
        return []


_JIKE_VOICE_SAMPLES = _load_jike_voice_samples()


def _pick_voice() -> str:
    import random
    if _JIKE_VOICE_SAMPLES:
        s = random.choice(_JIKE_VOICE_SAMPLES)
        return (
            "参照下面这条**即刻真实用户**动态的说话风格来写（学它的语气、节奏、用词、情绪、"
            "第一人称的随手感——但别抄它的内容/话题，也别提它，只借口吻）：\n「" + s + "」"
        )
    return random.choice(CONTENT_VOICES)

def _load_content_constitution() -> str:
    """把 SSOT 原文放进长上下文；部署包若暂缺 docs，则用严格核心摘要兜底。"""
    path = Path(__file__).resolve().parents[3] / "docs" / "CONTENT_CONSTITUTION.md"
    try:
        return path.read_text(encoding="utf-8")
    except OSError:
        logger.warning("未找到内容宪法文件 %s，AI 将使用内置核心规则", path)
        return "作品而非原料；吸引力五维；必须有成果证据与可验证体验；标题结果导向；宁缺毋滥。"


_CONTENT_CONSTITUTION = _load_content_constitution()
_SCORING_EXAMPLES = """
校准例 1（好）：标题“只画一次角色，换十个场景也不会变脸”，有角色多场景对比图、可下载工作流。
判定：is_work=true, work_form=workflow, access_friction=install；hook/visual/surprise 应高分。
校准例 2（好）：一段完整提示词能把流水账改成分镜脚本，正文直接给出可复制提示词和前后结果图。
判定：is_work=true, work_form=prompt, experience_type=prompt_content；没有 URL 也可发布。
校准例 3（好但有门槛）：专门把普通话微调成某地方言的模型，有音频对比和模型页，需要本地环境。
判定：is_work=true, work_form=model, access_friction=technical；不能因技术门槛误判为原料。
校准例 4（坏）：通用向量数据库 SDK，标题是“高性能开源项目推荐”，封面只有 GitHub 社交卡。
判定：is_work=false（原料），proof=null；star 再高也不能挽救。
校准例 5（坏）：公司官网首页截图配“一个 AI 效率工具”，没有最终效果、演示或具体场景。
判定：即使是产品，hook_clarity/visual_impact 应低，proof=null。
校准例 6（坏）：纯教程、资讯盘点、卖课引流或转发别人的十个工具，没有自己展示的完整作品。
判定：is_work=false，并给出明确 rejection reason/risk flag。
"""
_SYSTEM_PROMPT = """你是 kankan 冷启动阶段的内容总编。下面是完整、唯一有效的《内容宪法 v1.1》；
旧的 consumer_ready、旧 fun/fresh/useful 分数和“GitHub 天然可发布”等规则全部作废。

你必须先判作品/原料，再独立给五个吸引力分项与 value_score，绝不自己计算 attraction_score。
标题必须给两个真正不同的结果导向候选，每个 12-28 个可见字符；先说效果，不以项目名/模型名/技术名开头。
只依据输入事实，不编造体验入口、效果、作者或实现步骤。模型/工作流/提示词只要是有具体用途的完整作品就可收，
即使需要安装或技术环境，也应通过 access_friction=install/technical 表达，不能误判成原料。
selected_proof_media_index 只能选择输入媒体清单中确实能证明最终效果的一项；logo、社交卡、官网首页截图必须返回 null。
文案用具体自然的中文，避免营销腔；不要提来源平台，不要冒充原作者。实现步骤没把握就留空。

----- 内容宪法 v1.1 全文开始 -----
""" + _CONTENT_CONSTITUTION + """
----- 内容宪法 v1.1 全文结束 -----
""" + _SCORING_EXAMPLES


_POST_SYSTEM_PROMPT = """你是「AI 创意社区」的运营，把外部抓来的即刻/小红书上 AI 相关的**真人帖**，
**轻度改写**后发成社区动态。核心是"轻改"——不是重写、不是转述、不是扩写。

规则：
1. 【轻改，别重写】保留原帖的**长度、语气、句式、网感**。你只做三件事：① 原创化——换几个词/说法，避免逐字照搬（版权）；② 删掉跟主题无关的、太私人的、暴露原作者身份的部分；③ 顺一下通顺。**绝不扩写、不解释、不补背景、不加总结、不升华。**
2. 【长度跟着原帖·就是要短】原帖一两句你就一两句。**三四行就算多了**，绝不写成段落/小作文/报告。宁短、留白、有网感。
3. 【口吻】第一人称、口语、有网感，像真人随手发。可以有情绪、吐槽、半句话、口头禅；原帖有 emoji 就保留。别营销腔（"赋能/助力/一键/打造"），别客套（"今天给大家分享"）。
4. 【参照】输入里「口吻要求」是即刻真人的说话风格样本，学它的语气节奏，别抄它的内容。
5. 【不编造】不加原帖没有的事实/数据/链接。
6. 【标签】给 1-5 个中文话题标签（不带 # 号）。
7. 【风险】广告软文标 suspected_ad；纯搬运标 duplicate；可能侵权标 copyright_risk；信息量极低标 low_quality，并写 risk_note。"""


def _post_payload_for(candidate: CandidateContent) -> dict:
    raw = candidate.raw_json or {}
    return {
        "原文标题": raw.get("title") or candidate.title or "",
        "原文内容": (raw.get("text") or "")[:6000],
        "来源平台": candidate.source_platform or "未知",
        "来源链接": candidate.source_url or "",
        "口吻要求": _pick_voice(),  # 每条随机换一种真人腔调，避免批量同款
    }


def _payload_for(candidate: CandidateContent) -> dict:
    raw = candidate.raw_json or {}
    known = (raw.get("known_try_url") or "").strip()
    media = (candidate.media_json or {}).get("items", [])
    payload = {
        "原文标题": raw.get("title") or candidate.title or "",
        "原始正文": (raw.get("text") or "")[:6000],  # 防超长正文撑爆上下文
        "来源平台": candidate.source_platform or "未知",
        "来源链接": candidate.source_url or "",
        "原作者": candidate.original_author_name or "未识别",
        "媒体清单（按索引选择 proof）": [
            {
                "index": i,
                "url": item.get("url"),
                "media_type": item.get("media_type") or item.get("type") or "image",
                "width": item.get("width"),
                "height": item.get("height"),
                "alt": item.get("alt") or item.get("description"),
            }
            for i, item in enumerate(media[:20]) if isinstance(item, dict)
        ],
        "语言": candidate.language,
        # 每条随机换一个「写作角度」，让不同项目读起来像不同的人写的（治「一个模板腔」）。
        # 只换切入/语气，仍客观第三方（不注入第一人称口吻，避免"我做了"冒充作者）。
        "写作角度": _pick_angle(),
    }
    # 采集器已确定的体验入口：给模型当已知事实（写简介时可自然带出「可直接体验」），
    # 但 try_url 的最终值由 apply_analysis 用它兜底，不指望模型照抄。
    if known:
        payload["已知体验链接"] = known
    return payload


def claude_analyze(payload: dict) -> CandidateAnalysis:
    """真实整理：调 Claude 结构化输出，直接返回符合 CandidateAnalysis 的对象。
    SDK 自动重试限流/瞬时错误；这里只把"没配 key"翻译成人话。"""
    if not settings.anthropic_api_key:
        raise AppError(500, "INTERNAL", "未配置 ANTHROPIC_API_KEY，无法运行 AI 整理（冒烟测试请注入假 LLM）")
    from anthropic import Anthropic  # 惰性导入：没装 SDK 不影响服务其他部分

    client = Anthropic(api_key=settings.anthropic_api_key)
    response = client.messages.parse(
        model=settings.anthropic_model,
        max_tokens=4096,
        thinking={"type": "adaptive"},
        system=_SYSTEM_PROMPT,
        messages=[{
            "role": "user",
            "content": "请整理这条抓取内容：\n" + json.dumps(payload, ensure_ascii=False, indent=2),
        }],
        output_format=CandidateAnalysis,
    )
    return response.parsed_output


def _strip_json_fence(text: str) -> str:
    """稳妥剥掉模型偶尔套的 ```json 代码块围栏（json_object 模式一般不会，但兜一手）。"""
    t = (text or "").strip()
    if t.startswith("```"):
        t = t[3:]
        if t[:4].lower() == "json":
            t = t[4:]
        if t.endswith("```"):
            t = t[:-3]
    return t.strip()


def deepseek_analyze(payload: dict) -> CandidateAnalysis:
    """DeepSeek 整理：走 OpenAI 兼容接口 + JSON 模式，产出 JSON 再用 pydantic 校验。
    DeepSeek 无 Claude 的原生 parse，故用 json_object 模式 + 提示词带 schema；
    校验不过（枚举越界/字段缺）→ 抛异常，由 process_collected 记录跳过、下轮重跑。"""
    if not settings.deepseek_api_key:
        raise AppError(500, "INTERNAL", "未配置 DEEPSEEK_API_KEY，无法运行 DeepSeek 整理")
    from openai import OpenAI  # 惰性导入：没装 openai SDK 不影响服务其他部分

    client = OpenAI(api_key=settings.deepseek_api_key, base_url=settings.deepseek_base_url)
    schema = json.dumps(CandidateAnalysis.model_json_schema(), ensure_ascii=False)
    messages = [
        {
            "role": "system",
            "content": _SYSTEM_PROMPT
            + "\n\n只输出一个 JSON 对象，严格符合下面的 JSON Schema"
            "（字段名与枚举值照抄，不要多余字段、不要 markdown 代码块）：\n"
            + schema,
        },
        {
            "role": "user",
            "content": "请整理这条抓取内容，只输出 JSON：\n"
            + json.dumps(payload, ensure_ascii=False, indent=2),
        },
    ]
    # DeepSeek v4-flash 偶尔返回**空响应**或坏 JSON（transient）→ 重试几次，别一次空就判失败。
    last = "空响应"
    for attempt in range(3):
        resp = client.chat.completions.create(
            model=settings.deepseek_model,
            temperature=0.7,  # 略高让文风有差异，但别太高（0.85 会常吐坏 JSON）；开头模板由 _strip_definition_open 兜底
            response_format={"type": "json_object"},
            # v4-flash 是**推理模型**：答题前先烧 reasoning token。max_tokens 太小（如 2000）会被推理吃光、
            # 没 token 留给 JSON → finish=length、content 为空（踩过：2000→空，8000→正常）。给足 8000。
            max_tokens=8000,
            messages=messages,
        )
        text = _strip_json_fence(resp.choices[0].message.content or "")
        if not text:
            last = "空响应"
            continue
        try:
            return CandidateAnalysis.model_validate_json(text)
        except Exception as e:  # 坏 JSON / 字段不合规：重试，可能是 transient
            last = f"{type(e).__name__}"
    raise AppError(502, "AI_BAD_OUTPUT", f"DeepSeek 多次未产出有效 JSON（{last}）")


def claude_analyze_post(payload: dict) -> PostAnalysis:
    """动态改写（Claude）：结构化输出 PostAnalysis。"""
    if not settings.anthropic_api_key:
        raise AppError(500, "INTERNAL", "未配置 ANTHROPIC_API_KEY，无法运行动态改写")
    from anthropic import Anthropic

    client = Anthropic(api_key=settings.anthropic_api_key)
    response = client.messages.parse(
        model=settings.anthropic_model,
        max_tokens=2048,
        thinking={"type": "adaptive"},
        system=_POST_SYSTEM_PROMPT,
        messages=[{
            "role": "user",
            "content": "把这条内容改写成一条动态：\n" + json.dumps(payload, ensure_ascii=False, indent=2),
        }],
        output_format=PostAnalysis,
    )
    return response.parsed_output


def deepseek_analyze_post(payload: dict) -> PostAnalysis:
    """动态改写（DeepSeek）：OpenAI 兼容 + JSON 模式 → pydantic 校验。"""
    if not settings.deepseek_api_key:
        raise AppError(500, "INTERNAL", "未配置 DEEPSEEK_API_KEY，无法运行动态改写")
    from openai import OpenAI

    client = OpenAI(api_key=settings.deepseek_api_key, base_url=settings.deepseek_base_url)
    schema = json.dumps(PostAnalysis.model_json_schema(), ensure_ascii=False)
    resp = client.chat.completions.create(
        model=settings.deepseek_model,
        temperature=0.7,  # 动态要有人味/多样，温度比项目整理高一点
        response_format={"type": "json_object"},
        messages=[
            {
                "role": "system",
                "content": _POST_SYSTEM_PROMPT
                + "\n\n只输出一个 JSON 对象，严格符合下面的 JSON Schema"
                "（字段名与枚举值照抄，不要多余字段、不要 markdown 代码块）：\n"
                + schema,
            },
            {
                "role": "user",
                "content": "把这条内容改写成一条动态，只输出 JSON：\n"
                + json.dumps(payload, ensure_ascii=False, indent=2),
            },
        ],
    )
    text = _strip_json_fence(resp.choices[0].message.content or "")
    return PostAnalysis.model_validate_json(text)


def _paragraphize(text: Optional[str], min_len: int = 100) -> Optional[str]:
    """长文按句子切成 2~3 句一段、段间空行，便于阅读（用户要求：字数多适当换行）。
    模型不爱在 JSON 里加换行，这里确定性地补。已有换行的（模型自己分了段）就不动。"""
    if not text:
        return text
    t = text.strip()
    if len(t) <= min_len or "\n" in t:
        return t
    parts = re.split(r"(?<=[。！？!?])", t)  # 保留标点切句
    paras, cur = [], ""
    for s in parts:
        if not s.strip():
            continue
        cur += s
        if len(cur) >= 55:  # 攒够约一段就换行
            paras.append(cur)
            cur = ""
    if cur:
        paras.append(cur)
    return "\n\n".join(paras) if len(paras) > 1 else t


_DEF_OPEN = re.compile(r"^\s*[^，。！？\n]{1,22}?是一[个款种套项门]")


def _strip_definition_open(text: Optional[str]) -> Optional[str]:
    """去掉「X 是一个/一款/一种/一套 …」这种定义句开头——项目文案「一个模板腔」的根源。
    模型（尤其 summary）老爱这么起，prompt 压不住；这里确定性地砍掉首句那一小段，
    剩下的名词短语照读通顺（「OpenCut 是一款开源视频编辑器」→「开源视频编辑器」）。
    只在砍完仍有实质内容（≥8 字）时才砍，避免砍空。"""
    if not text:
        return text
    t = text.lstrip()
    m = _DEF_OPEN.match(t)
    if m:
        rest = t[m.end():].lstrip("，,、：: \n")
        if len(rest) >= 8:
            return rest
    return text


def get_analyzer() -> AnalyzeFn:
    """按 settings.ai_provider 选整理器：deepseek / claude（默认 claude）。"""
    return deepseek_analyze if settings.ai_provider == "deepseek" else claude_analyze


def get_post_analyzer() -> PostAnalyzeFn:
    """动态改写器：deepseek / claude（默认 claude）。"""
    return deepseek_analyze_post if settings.ai_provider == "deepseek" else claude_analyze_post


def compute_curation_score(scores: AnalysisScores) -> int:
    """内容宪法 v1.1 attraction_score；后端是唯一算分方。"""
    total = sum(getattr(scores, k) * w for k, w in SCORE_WEIGHTS.items())
    return round(total)


def _format_hint(steps: Optional[List[str]]) -> Optional[str]:
    """实现思路落库格式：标注"AI 推测"（admin 文档 §4 要求），分步编号。"""
    steps = [s.strip() for s in (steps or []) if s and s.strip()]
    if not steps:
        return None
    return "【AI 推测，待人工核对】" + "；".join(f"{i}. {s}" for i, s in enumerate(steps[:3], 1))


# 帖子类来源：source_url 是"出处帖子页"而非体验入口，不能当 try_url（真链接在正文里，走 known_try_url）。
# 成品类来源（PH/hackernews/hellogithub/githubdaily/manual/导航）不在此列——它们的 source_url 就是产品链接。
_POST_SRC_PLATFORMS = {"douyin", "xiaohongshu", "jike", "x", "weibo"}


def apply_analysis(db: Session, candidate: CandidateContent, analysis: CandidateAnalysis) -> None:
    """整理结果写回候选行：ai_processed；字段齐到能过发布准入的，直接推进 pending_review
    进审核队列，缺料的（如没封面）停在 ai_processed 等运营补。不在这里 commit。"""
    titles = [t.strip() for t in analysis.title_candidates[:2]]
    candidate.title_candidates = titles
    candidate.title = titles[0][:80]
    candidate.tagline = (_strip_definition_open(analysis.hook_sentence) or "")[:140]
    candidate.summary = _strip_definition_open(analysis.summary)[:500]
    candidate.description = _paragraphize(_strip_definition_open(analysis.description))
    candidate.category = analysis.category
    candidate.domains = list(dict.fromkeys(analysis.domains))  # 去重保序
    candidate.tools = analysis.tools[:10]
    candidate.tags_json = {"items": analysis.tags[:5]}
    candidate.target_users = analysis.target_users[:5] or None
    candidate.use_cases = analysis.use_cases[:5] or None
    candidate.ai_implementation_hint = _format_hint(analysis.implementation_steps)
    candidate.is_work = analysis.is_work
    candidate.work_rejection_reason = analysis.work_rejection_reason
    candidate.work_form = analysis.work_form
    candidate.creator_type = analysis.creator_type
    candidate.access_friction = analysis.access_friction
    candidate.hook_clarity = analysis.scores.hook_clarity
    candidate.visual_impact = analysis.scores.visual_impact
    candidate.surprise = analysis.scores.surprise
    candidate.tryability = analysis.scores.tryability
    candidate.shareability = analysis.scores.shareability
    candidate.attraction_score = compute_curation_score(analysis.scores)
    candidate.ai_curation_score = candidate.attraction_score  # 兼容旧后台排序/徽章
    candidate.value_score = analysis.value_score
    candidate.policy_version = POLICY_VERSION
    model_name = settings.deepseek_model if settings.ai_provider == "deepseek" else settings.anthropic_model
    candidate.score_version = f"constitution-{POLICY_VERSION}:{model_name}"
    candidate.scores_json = {
        **analysis.scores.model_dump(),
        "weights": SCORE_WEIGHTS,
        "attraction_score": candidate.attraction_score,
        "value_score": candidate.value_score,
        "policy_version": POLICY_VERSION,
        "score_version": candidate.score_version,
        **({"why_recommend": analysis.why_recommend} if analysis.why_recommend else {}),
    }
    candidate.risk_flags = list(dict.fromkeys(analysis.risk_flags))
    candidate.risk_note = analysis.risk_note
    candidate.selected_proof_media = select_proof_media(candidate, analysis.selected_proof_media_index)
    candidate.cover_media_url = (
        candidate.selected_proof_media.get("url") if candidate.selected_proof_media else None
    )
    candidate.is_strong_visual = bool(candidate.visual_impact >= 80 and candidate.selected_proof_media)

    # 体验入口：采集器确定性外链优先于模型抄写；内容型体验不强塞 URL。
    _known = ((candidate.raw_json or {}).get("known_try_url") or "").strip()
    _tu = _known or (analysis.experience_url or "").strip() or None
    _src = candidate.source_url or ""
    # 帖子类来源（抖音/小红书/即刻/X/微博）的 source_url 是「出处帖子页」不是体验入口——落到它上就清空。
    # 成品类来源（PH / Show HN / HelloGitHub / GitHubDaily / 手动加 / 导航站）的 source_url **就是产品链接
    # 本身**，必须保留（否则会被误杀成"无链接"卡在 ai_processed——真踩过的坑）。
    if _tu and _tu == _src and (candidate.source_platform or "") in _POST_SRC_PLATFORMS:
        _tu = None
    if _tu and ("douyin.com/video" in _tu or "xiaohongshu.com" in _tu
                or "/note/" in _tu or "v.douyin.com" in _tu):
        _tu = None
    candidate.experience_type = analysis.experience_type
    candidate.experience_url = _tu
    candidate.experience_content = (analysis.experience_content or "").strip() or None
    candidate.try_url = _tu  # 旧客户端兼容；新 gate 只看 experience 三件套
    candidate.is_direct_tryable = bool(
        (
            candidate.experience_type in {"web", "video", "gallery", "game"}
            and candidate.experience_url
        )
        or (
            candidate.experience_type == "prompt_content"
            and candidate.experience_content
        )
    )
    candidate.ai_analysis_json = analysis.model_dump(mode="json")
    candidate.human_override_json = None
    candidate.override_reason = None

    candidate.status = "ai_processed"
    if not analysis.is_work:
        candidate.status = "discarded"
        return
    if candidate.attraction_score < 60:
        candidate.status = "discarded"
        return
    if candidate.attraction_score < 70:
        return  # 60～69 留候选池，不发布
    try:
        check_publish_gate(candidate)  # 与 approve 同一把尺子，避免审核员点开才发现缺料
        candidate.status = "pending_review"
    except AppError:
        pass  # 缺封面/字段不齐：停在 ai_processed，后台可编辑补齐后再走


def apply_post_analysis(db: Session, candidate: CandidateContent, analysis: PostAnalysis) -> None:
    """动态改写结果写回候选行。正文存 summary、标签存 tags_json（approve 时读它们建 Post）。
    字段齐（正文≥20、标签≥1）就推进 pending_review，否则停 ai_processed。不在这里 commit。"""
    candidate.summary = analysis.content[:500]
    candidate.tags_json = {"items": analysis.tags[:5]}
    candidate.risk_flags = list(dict.fromkeys(analysis.risk_flags))
    candidate.risk_note = analysis.risk_note

    candidate.status = "ai_processed"
    try:
        check_post_gate(candidate)  # 与 approve 同一把尺子
        candidate.status = "pending_review"
    except AppError:
        pass


def process_collected(
    db: Session, limit: int = 20, analyze: Optional[AnalyzeFn] = None,
    analyze_post: Optional[PostAnalyzeFn] = None, source_platform: Optional[str] = None,
) -> Dict[str, int]:
    """批量整理：按入池顺序取 ai_collected 的候选逐条整理。单条失败记日志跳过
    （下轮重跑会再取到它），不让一条坏数据卡死整批。返回统计。"""
    analyze = analyze or get_analyzer()
    analyze_post = analyze_post or get_post_analyzer()
    stats = {"processed": 0, "to_review": 0, "failed": 0, "capped": 0}
    stmt = select(CandidateContent).where(CandidateContent.status == "ai_collected")
    if source_platform:
        stmt = stmt.where(CandidateContent.source_platform == source_platform)
    candidates = db.execute(stmt.order_by(CandidateContent.created_at).limit(limit)).scalars().all()

    consecutive_failures = 0
    breaker = settings.ai_failure_circuit_breaker
    for candidate in candidates:
        # 成本护栏：当日调用额度用尽 → 停整理，剩下的下轮再跑（不丢，状态仍 ai_collected）。
        if not ai_budget.try_consume(1):
            stats["capped"] = len(candidates) - stats["processed"] - stats["failed"]
            logger.warning("AI 整理触及当日额度上限，本批提前结束")
            break
        try:
            if candidate.content_kind == "post":
                apply_post_analysis(db, candidate, analyze_post(_post_payload_for(candidate)))
            else:
                apply_analysis(db, candidate, analyze(_payload_for(candidate)))
            db.commit()
            stats["processed"] += 1
            consecutive_failures = 0
            if candidate.status == "pending_review":
                stats["to_review"] += 1
        except Exception:
            db.rollback()
            stats["failed"] += 1
            consecutive_failures += 1
            logger.exception("候选整理失败 candidate_id=%s", candidate.id)
            # 连续失败熔断：多半 key 失效/额度耗尽/网络断，别继续烧钱重试整批。
            if breaker > 0 and consecutive_failures >= breaker:
                logger.error("AI 整理连续失败 %s 次，触发熔断，本批中止", consecutive_failures)
                break
    return stats
