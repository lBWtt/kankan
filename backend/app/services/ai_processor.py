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
from typing import Callable, Dict, List, Literal, Optional

from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.errors import AppError
from app.models import CandidateContent
from app.models.enums import CATEGORY, DOMAIN
from app.services import ai_budget
from app.services.candidates import check_post_gate, check_publish_gate

logger = logging.getLogger("app.ai_processor")

# 风险标记的固定取值（admin 文档 §4：疑似广告/重复/侵权/低质，AI 标了运营必须人工确认）
RISK_FLAGS = ("suspected_ad", "duplicate", "copyright_risk", "low_quality")

# ai_curation_score 权重：趣味25%、可分享25%、新鲜20%、实用15%、可去用15%
# （定位=去看/去用：把旧的"可复刻15%"换成"可去用"——用户能不能直接点进去用/体验。）
SCORE_WEIGHTS = {"fun": 0.25, "shareable": 0.25, "fresh": 0.20, "useful": 0.15, "usable": 0.15}


class AnalysisScores(BaseModel):
    """五个维度各 0-100；加权合成在 Python 里算，不让模型做算术。"""
    fun: int = Field(ge=0, le=100, description="趣味：普通用户看到会不会觉得有意思")
    shareable: int = Field(ge=0, le=100, description="可分享：会不会想转给同事/朋友")
    fresh: int = Field(ge=0, le=100, description="新鲜：是不是没见过的新玩法")
    useful: int = Field(ge=0, le=100, description="实用：对目标人群有没有现实落点")
    usable: int = Field(ge=0, le=100, description="可去用：用户能不能直接点进去用/体验（有可用链接、开箱即用得分高；只是看看/需要自己从头搭得分低）")


class CandidateAnalysis(BaseModel):
    """AI 整理的全部产出（结构化输出 schema；中文面向用户，枚举值面向系统）。"""
    title: str = Field(min_length=2, max_length=80, description="中文标题，6-40 字最佳，清楚不标题党")
    tagline: str = Field(min_length=5, max_length=140, description="一句话亮点，让普通用户 3 秒懂 AI 做了什么")
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
    risk_flags: List[Literal[RISK_FLAGS]] = Field(  # type: ignore[valid-type]
        default_factory=list, description="风险标记：suspected_ad 疑似广告 / duplicate 疑似重复 / copyright_risk 疑似侵权 / low_quality 低质"
    )
    risk_note: Optional[str] = Field(default=None, description="标了风险时一句话说明原因")
    why_recommend: Optional[str] = Field(default=None, description="给运营看的一句话推荐理由")
    # 小红书/抖音 Vibe Coding 专用：分清"真开发者成果" vs 广告/水/教程 + 提体验入口。
    is_maker_showcase: bool = Field(
        default=True,
        description="是不是**真开发者做出来的成果**（有人做了个能用/能看的东西：小程序/APP/网站/工具，配了截图/demo）。"
        "**不是**的情形要判 False：卖课/培训/引流广告、纯教程无成品、纯观点/资讯、转发搬运、水贴。GitHub 源恒 True。",
    )
    try_url: Optional[str] = Field(
        default=None,
        description="**体验入口**：从原文提取能去试的东西——网址(http)、小程序名、公众号、TestFlight 等。"
        "有就填、优先填 http 链接；小红书常屏蔽链接只给'主页/小程序名'，那就填能识别的那个名字；实在没有才 null。不编造。",
    )


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

_SYSTEM_PROMPT = f"""你是「AI 创意项目发现 App」的内容编辑。App 给中文用户策展"别人用 AI 做成了什么、你能直接用上"的真实用例。

把抓取的原始内容整理成候选卡片字段。规则：
1. 标题/亮点/简介一律中文（原文是外文就翻译+提炼），写给普通用户看，不堆术语、不标题党。
2. 只依据原文信息，不编造。工具清单原文提到才填；实现思路（implementation_steps）只在来源和工具都清晰、思路可信时给，最多 3 步，没把握就 null——宁缺勿错，这条会展示给高意图用户，幻觉代价最大。
3. 评分按维度独立打：趣味（普通用户觉得有意思吗）、可分享（想转发吗）、新鲜（没见过吗）、实用（有现实落点吗）、可去用（用户能不能直接点进去用/体验——有可用链接、开箱即用给高分；只能看看、需要自己从头搭给低分）。诚实打分，平庸内容就给低分。
4. 风险：广告软文味重标 suspected_ad；像搬运拼接标 duplicate；图片/内容可能侵权标 copyright_risk；信息量极低/纯晒图无方法标 low_quality。标了就写 risk_note。
5. 优先收录标准：有趣新鲜、展示强、普通用户可懂、有现实落点、可收藏可分享。纯论文/技术库、无图无方法的内容评分应该很低。
6. 【口吻像真人，别像 AI】用平实、具体、有细节的中文，像一个懂行的朋友在介绍，不是营销文案。禁止空泛套话与营销腔（如"赋能/助力/一键/轻松搞定/打造/让 X 更简单/无限可能/开启新纪元"），少用感叹号，别堆形容词。能写具体数字、具体做法、具体效果就写具体。
7. 【每条尽量充实】description 从原文提炼背景、具体怎么做、用了什么、效果/数据、值得注意的细节，写成 3-6 句的完整介绍，别只留一句或留空；target_users / use_cases 尽量给全。但一切以原文为准，信息不足就如实少写，绝不编造凑数。
8. 【直接介绍项目本身 + 有网感 + 别套模板】直接介绍这个项目/工具**是什么、能干嘛、怎么用、亮点在哪**，把要点讲清楚。
   **硬性禁止出现指向来源/作者的词**：作者、开发者、博主、网友、一位用户、有人做了、up主、据说、据原帖、转发、抖音/小红书/GitHub 上… 一个都不许出现——只介绍"这个东西"本身，让用户留在站内，别引导去追原作者/原帖。也别用「我做了/我试了」冒充。
   **第一句硬禁止**用「{{项目名}}是一个/是一款/是一套/是一种…」这种定义句式（这是最大的模板腔来源，违反就算不合格）。tagline、summary、description 的**开头都不许**这样起。
   **严格按输入里给的「写作角度」定这条的切入和语气**，第一句直接切进去，示例（不同角度不同开头）：
     · 亮点先行：「9 分钟就能搓出一个能跑的 App。」
     · 场景切入：「每周写周报头疼？把工作流水丢给它，自动整理成结构化周报。」
     · 冷静测评：「用了两周，最省事的是它能……」
     · 技术视角：「靠节点连线把出图流程拆成一块块，……」
     · 反差开场：「不用写一行代码，……」
   让不同项目开头各不一样、像不同的人写的，别所有项目一个说明书腔。口吻自然、有网感，但项目关键点（能干嘛/怎么用/好在哪）必须交代到。structured 字段（category/domains/tools 等）照常客观。
9. 【分清"我做的作品" vs "教程/介绍/卖课"——小红书/抖音关键，最容易判反！】is_maker_showcase=True 只给一种情况：**发帖人自己用 AI 做出来的一个具体作品**（小程序/APP/网站/游戏/工具/原型），帖子在晒它、展示它——**哪怕只是原型/demo 也算 True**。
   判 False 的情形（很常见，别漏）：① 教别人怎么用某工具（标题/正文含"教程/入门/上手/安装/速通/攻略/保姆级/从0到1/教学"）；② 介绍·测评·盘点别人的工具、或"AI工具清单"；③ 纯资讯/观点；④ 卖课/培训/引流/加微信（同时标 suspected_ad）；⑤ 转发/水贴。
   **一句话：在秀「我做的东西」=True；在教别人、介绍别人的工具、卖课 =False。** GitHub 源恒 True。
10. 【提体验入口 + 有链接优先】try_url：把原文里能去试的入口提出来（网址 / 小程序名 / 公众号 / TestFlight）。**有可去试入口的内容更有价值——usable 维度给更高分**；纯展示、无处可试的 usable 给低分。别编造链接。"""


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
    payload = {
        "原文标题": raw.get("title") or candidate.title or "",
        "原始正文": (raw.get("text") or "")[:6000],  # 防超长正文撑爆上下文
        "来源平台": candidate.source_platform or "未知",
        "来源链接": candidate.source_url or "",
        "原作者": candidate.original_author_name or "未识别",
        "媒体数量": len((candidate.media_json or {}).get("items", [])),
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
    resp = client.chat.completions.create(
        model=settings.deepseek_model,
        temperature=0.7,  # 略高让文风有差异，但别太高（0.85 会常吐坏 JSON）；开头模板由 _strip_definition_open 兜底
        response_format={"type": "json_object"},
        messages=[
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
        ],
    )
    text = _strip_json_fence(resp.choices[0].message.content or "")
    return CandidateAnalysis.model_validate_json(text)


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
    """ai_curation_score = 加权合成（PRD §10 权重），四舍五入到整数。"""
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
    candidate.title = analysis.title[:80]
    # 砍掉「X 是一个/一款…」定义句开头（模板腔根源，prompt 压不住，确定性兜底）。
    candidate.tagline = _strip_definition_open(analysis.tagline)[:140]
    candidate.summary = _strip_definition_open(analysis.summary)[:500]
    candidate.description = _paragraphize(_strip_definition_open(analysis.description))
    candidate.category = analysis.category
    candidate.domains = list(dict.fromkeys(analysis.domains))  # 去重保序
    candidate.tools = analysis.tools[:10]
    candidate.tags_json = {"items": analysis.tags[:5]}
    candidate.target_users = analysis.target_users[:5] or None
    candidate.use_cases = analysis.use_cases[:5] or None
    candidate.ai_implementation_hint = _format_hint(analysis.implementation_steps)
    candidate.ai_curation_score = compute_curation_score(analysis.scores)
    candidate.scores_json = {
        **analysis.scores.model_dump(),
        "weights": SCORE_WEIGHTS,
        "composite": candidate.ai_curation_score,
        **({"why_recommend": analysis.why_recommend} if analysis.why_recommend else {}),
    }
    candidate.risk_flags = list(dict.fromkeys(analysis.risk_flags))
    candidate.risk_note = analysis.risk_note
    # 体验入口：采集器给的确定性外链优先（PH 产品官网 / GitHub homepage / X 外链），
    # 模型自己提的次之——别让模型从正文瞎猜漏掉真链接。
    _tu = (analysis.try_url or "").strip() or (candidate.raw_json or {}).get("known_try_url") or None
    _src = candidate.source_url or ""
    # GitHub 仓库本身就是「去看/去用」入口——没别的链接时用仓库地址兜底（用户明确：GitHub 链接算可去用）。
    if not _tu and "github.com/" in _src:
        _tu = _src
    # 帖子类来源（抖音/小红书/即刻/X/微博）的 source_url 是「出处帖子页」不是体验入口——落到它上就清空。
    # 成品类来源（PH / Show HN / HelloGitHub / GitHubDaily / 手动加 / 导航站）的 source_url **就是产品链接
    # 本身**，必须保留（否则会被误杀成"无链接"卡在 ai_processed——真踩过的坑）。
    if _tu and _tu == _src and (candidate.source_platform or "") in _POST_SRC_PLATFORMS:
        _tu = None
    if _tu and ("douyin.com/video" in _tu or "xiaohongshu.com" in _tu
                or "/note/" in _tu or "v.douyin.com" in _tu):
        _tu = None
    candidate.try_url = _tu
    # 评分红线（用户硬要求）：没有「可去用链接」的项目分数压到底（≤20），绝不让它浮上审核/推荐队列顶部。
    if not candidate.try_url:
        _capped = min(candidate.ai_curation_score or 0, 20)
        candidate.ai_curation_score = _capped
        candidate.scores_json = {
            **(candidate.scores_json or {}), "composite": _capped, "no_try_url_penalty": True,
        }

    candidate.status = "ai_processed"
    # 分清真成果：不是开发者成果（广告/教程/水）→ 不进待审核队列，留 ai_processed 让运营筛掉。
    # GitHub 源 is_maker_showcase 恒 True，不受影响；主要拦小红书/抖音的广告水贴。
    if not analysis.is_maker_showcase:
        if "low_quality" not in candidate.risk_flags:
            candidate.risk_flags = list(candidate.risk_flags) + ["low_quality"]
        candidate.risk_note = (candidate.risk_note or "") + " ｜非开发者成果(广告/教程/水)，已拦在审核前"
        return
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
    analyze_post: Optional[PostAnalyzeFn] = None,
) -> Dict[str, int]:
    """批量整理：按入池顺序取 ai_collected 的候选逐条整理。单条失败记日志跳过
    （下轮重跑会再取到它），不让一条坏数据卡死整批。返回统计。"""
    analyze = analyze or get_analyzer()
    analyze_post = analyze_post or get_post_analyzer()
    stats = {"processed": 0, "to_review": 0, "failed": 0, "capped": 0}
    candidates = db.execute(
        select(CandidateContent)
        .where(CandidateContent.status == "ai_collected")
        .order_by(CandidateContent.created_at)
        .limit(limit)
    ).scalars().all()

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
