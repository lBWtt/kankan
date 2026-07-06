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
from typing import Callable, Dict, List, Literal, Optional

from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.errors import AppError
from app.models import CandidateContent
from app.models.enums import CATEGORY, DOMAIN
from app.services.candidates import check_publish_gate

logger = logging.getLogger("app.ai_processor")

# 风险标记的固定取值（admin 文档 §4：疑似广告/重复/侵权/低质，AI 标了运营必须人工确认）
RISK_FLAGS = ("suspected_ad", "duplicate", "copyright_risk", "low_quality")

# ai_curation_score 权重（PRD §10，一字不差）：趣味25%、可分享25%、新鲜20%、实用15%、可复刻15%
SCORE_WEIGHTS = {"fun": 0.25, "shareable": 0.25, "fresh": 0.20, "useful": 0.15, "reproducible": 0.15}


class AnalysisScores(BaseModel):
    """五个维度各 0-100；加权合成在 Python 里算，不让模型做算术。"""
    fun: int = Field(ge=0, le=100, description="趣味：普通用户看到会不会觉得有意思")
    shareable: int = Field(ge=0, le=100, description="可分享：会不会想转给同事/朋友")
    fresh: int = Field(ge=0, le=100, description="新鲜：是不是没见过的新玩法")
    useful: int = Field(ge=0, le=100, description="实用：对目标人群有没有现实落点")
    reproducible: int = Field(ge=0, le=100, description="可复刻：普通人照着做能不能做出来")


class CandidateAnalysis(BaseModel):
    """AI 整理的全部产出（结构化输出 schema；中文面向用户，枚举值面向系统）。"""
    title: str = Field(min_length=2, max_length=80, description="中文标题，6-40 字最佳，清楚不标题党")
    tagline: str = Field(min_length=5, max_length=140, description="一句话亮点，让普通用户 3 秒懂 AI 做了什么")
    summary: str = Field(min_length=20, max_length=500, description="中文简介，50-500 字，用户语言不堆术语")
    description: Optional[str] = Field(default=None, description="详细介绍：背景、做了什么、效果如何；没有更多信息就留空")
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


# 整理函数的形状：拿候选原料 dict，返回 CandidateAnalysis。
# 真实实现是 claude_analyze；冒烟测试注入假实现，不花 API 钱。
AnalyzeFn = Callable[[dict], CandidateAnalysis]

_SYSTEM_PROMPT = f"""你是「AI 创意项目发现 App」的内容编辑。App 给中文用户策展"别人用 AI 做成了什么、你能直接用上"的真实用例。

把抓取的原始内容整理成候选卡片字段。规则：
1. 标题/亮点/简介一律中文（原文是外文就翻译+提炼），写给普通用户看，不堆术语、不标题党。
2. 只依据原文信息，不编造。工具清单原文提到才填；实现思路（implementation_steps）只在来源和工具都清晰、思路可信时给，最多 3 步，没把握就 null——宁缺勿错，这条会展示给高意图用户，幻觉代价最大。
3. 评分按维度独立打：趣味（普通用户觉得有意思吗）、可分享（想转发吗）、新鲜（没见过吗）、实用（有现实落点吗）、可复刻（普通人照着能做吗）。诚实打分，平庸内容就给低分。
4. 风险：广告软文味重标 suspected_ad；像搬运拼接标 duplicate；图片/内容可能侵权标 copyright_risk；信息量极低/纯晒图无方法标 low_quality。标了就写 risk_note。
5. 优先收录标准：有趣新鲜、展示强、普通用户可懂、有现实落点、可收藏可分享。纯论文/技术库、无图无方法的内容评分应该很低。"""


def _payload_for(candidate: CandidateContent) -> dict:
    raw = candidate.raw_json or {}
    return {
        "原文标题": raw.get("title") or candidate.title or "",
        "原始正文": (raw.get("text") or "")[:6000],  # 防超长正文撑爆上下文
        "来源平台": candidate.source_platform or "未知",
        "来源链接": candidate.source_url or "",
        "原作者": candidate.original_author_name or "未识别",
        "媒体数量": len((candidate.media_json or {}).get("items", [])),
        "语言": candidate.language,
    }


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


def apply_analysis(db: Session, candidate: CandidateContent, analysis: CandidateAnalysis) -> None:
    """整理结果写回候选行：ai_processed；字段齐到能过发布准入的，直接推进 pending_review
    进审核队列，缺料的（如没封面）停在 ai_processed 等运营补。不在这里 commit。"""
    candidate.title = analysis.title[:80]
    candidate.tagline = analysis.tagline[:140]
    candidate.summary = analysis.summary[:500]
    candidate.description = analysis.description
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

    candidate.status = "ai_processed"
    try:
        check_publish_gate(candidate)  # 与 approve 同一把尺子，避免审核员点开才发现缺料
        candidate.status = "pending_review"
    except AppError:
        pass  # 缺封面/字段不齐：停在 ai_processed，后台可编辑补齐后再走


def process_collected(
    db: Session, limit: int = 20, analyze: Optional[AnalyzeFn] = None
) -> Dict[str, int]:
    """批量整理：按入池顺序取 ai_collected 的候选逐条整理。单条失败记日志跳过
    （下轮重跑会再取到它），不让一条坏数据卡死整批。返回统计。"""
    analyze = analyze or claude_analyze
    stats = {"processed": 0, "to_review": 0, "failed": 0}
    candidates = db.execute(
        select(CandidateContent)
        .where(CandidateContent.status == "ai_collected")
        .order_by(CandidateContent.created_at)
        .limit(limit)
    ).scalars().all()

    for candidate in candidates:
        try:
            analysis = analyze(_payload_for(candidate))
            apply_analysis(db, candidate, analysis)
            db.commit()
            stats["processed"] += 1
            if candidate.status == "pending_review":
                stats["to_review"] += 1
        except Exception:
            db.rollback()
            stats["failed"] += 1
            logger.exception("候选整理失败 candidate_id=%s", candidate.id)
    return stats
