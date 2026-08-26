# ============================================================
# 这个文件是干什么的：采集标准的**唯一真源（SSOT）**——定义"什么样的外部内容够格进候选池"。
#   这是**机械粗筛**（够不够火 + 完不完整），便宜、砍长尾；内容好不好由下游 DeepSeek
#   五维分把关，别在这里判语义质量。
# 它对应产品里的什么功能：② 采集入池前的第一道闸（PIPELINE_PLAN 决策：热度是粗筛不是标准）。
#
# 粗筛只做两件事（都和"定位"无关，纯砍长尾噪声）：
#   1) 够不够火——收藏/点赞热度门槛（低于门槛的长尾直接砍，省 DeepSeek 钱）；
#   2) 完不完整+能不能去体验——有图/视频 + 正文够长 + 有可点开的外链（http/https）。
# 定位="去看/去用/去体验"：内容好不好、能不能直接上手，交下游 DeepSeek 判（见 ai_processor）。
# 不再用"收藏率"当红线——那是旧"复刻"概念，会误砍"用了就走"的好内容。
#
# 无第三方依赖（纯 stdlib），adapter / prefilter 都 import 它，改阈值只改这一处。
# ============================================================
import re
from typing import Optional

# 平台 → 热度门槛（collects 收藏为主，likes 点赞为辅）。圈子大小不同，门槛不同。
# 起步值：先跑一周看真实分布再收紧（阈值是可调旋钮，不是铁律）。
PLATFORM_THRESHOLDS = {
    # 抖音/小红书/快手：链接不外露，产品链接靠**人工补**，所以只留「真正火」的（赞+收藏都要高，见
    # REQUIRE_BOTH_PLATFORMS），把量压到很小、只挑最值得人工去找链接的爆款。门槛调高、可再调。
    "xiaohongshu": {"collects": 1000, "likes": 3000},
    "douyin": {"collects": 2000, "likes": 20000},   # 抖音赞虚高，收藏/转发更真，故收藏门槛也拉高
    "kuaishou": {"collects": 2000, "likes": 20000},
    "bilibili": {"collects": 300, "likes": 1000},
    "jike": {"collects": 20, "likes": 50},          # 圈子小浓度高，门槛低很多
    # GitHub：collector 已按 star 增速/主题白名单精选，这里只做**完整性+活性兜底**门槛。
    # 映射：collects=stars（主信号）、likes=forks。star≥30 或 forks≥5 即过（低门槛，真筛在 collector）。
    "github": {"collects": 30, "likes": 5},
}
DEFAULT_THRESHOLD = {"collects": 200, "likes": 500}

# 「赞和收藏都要够」的平台（2026-08-09 改）：抖音/小红书/快手 链接不外露，只能人工补链接，
# 所以只挑**真正的爆款**——收藏 AND 点赞**同时**过高门槛（普通「或」太松会放进一堆没链接的水贴）。
# 这些进池后没 try_url，会停在 ai_processed 等你人工补链接+审。别的平台仍是「收藏或点赞任一达标」。
REQUIRE_BOTH_PLATFORMS = {"douyin", "xiaohongshu", "kuaishou"}

# 完整性门槛（无图/纯晒图/无外链，粗筛就砍）
MIN_TEXT_LEN = 10   # 正文太短多半是纯晒图无内容
REQUIRE_MEDIA = True  # 至少 1 张图或 1 条视频
# 定位=去体验：必须有可点开的外链（http/https），否则"没东西可以去用/去看"。
REQUIRE_SOURCE_URL = True

_NUM = re.compile(r"[\d.]+")
_HTTP_URL = re.compile(r"^https?://", re.IGNORECASE)


def _is_http_url(u) -> bool:
    return bool(u) and bool(_HTTP_URL.match(str(u).strip()))


def parse_count(value) -> int:
    """把平台的中文计数串转成整数：'10万+'→100000，'1.2万'→12000，'7468'→7468，''→0。
    兼容 万(1e4)/亿(1e8)、逗号、加号、空串。拿不准就当 0（宁可少收不误判高热）。"""
    if value is None:
        return 0
    if isinstance(value, (int, float)):
        return int(value)
    s = str(value).strip().replace(",", "").replace("+", "")
    if not s:
        return 0
    m = _NUM.search(s)
    if not m:
        return 0
    num = float(m.group())
    if "亿" in s:
        num *= 100_000_000
    elif "万" in s or "w" in s.lower():
        num *= 10_000
    return int(num)


def thresholds_for(platform: Optional[str]) -> dict:
    return PLATFORM_THRESHOLDS.get((platform or "").lower(), DEFAULT_THRESHOLD)


def evaluate(item: dict, platform: Optional[str]) -> dict:
    """按标准评一条 adapter 标准条目。返回 {passed, reasons, metrics}。
    - reasons 为空 = 通过；否则列出每条不通过的原因（可审计，让人看清为什么砍）。
    - 热度：收藏≥门槛 或 点赞≥门槛（任一达标即过，粗筛从宽；精判交 DeepSeek）。
    - 完整性：有图/视频 且 正文≥MIN_TEXT_LEN。"""
    eng = item.get("engagement") or {}
    likes = parse_count(eng.get("likes"))
    collects = parse_count(eng.get("collects"))
    comments = parse_count(eng.get("comments"))
    shares = parse_count(eng.get("shares"))
    text = (item.get("text") or "").strip()
    media = item.get("media") or []
    source_url = (item.get("source_url") or "").strip()
    th = thresholds_for(platform)

    reasons = []
    # 收藏率仅作参考指标（不再当红线，见文件头）：收藏/点赞。
    save_rate = round(collects / likes, 3) if likes > 0 else None

    # 热度粗筛。抖音/小红书/快手（链接靠人工补）：**收藏 AND 点赞都要过高门槛**，只留真爆款；
    # 其它平台：收藏 或 点赞 任一达标即过（从宽，精判交 DeepSeek）。
    if (platform or "").lower() in REQUIRE_BOTH_PLATFORMS:
        if collects < th["collects"] or likes < th["likes"]:
            reasons.append(
                f"未达爆款门槛（需 收藏≥{th['collects']} 且 点赞≥{th['likes']}；实际 收藏{collects}/点赞{likes}）"
            )
    elif collects < th["collects"] and likes < th["likes"]:
        reasons.append(
            f"热度不足（收藏 {collects}<{th['collects']} 且 点赞 {likes}<{th['likes']}）"
        )
    # 完整性
    if REQUIRE_MEDIA and not media:
        reasons.append("无图无视频")
    if len(text) < MIN_TEXT_LEN:
        reasons.append(f"正文过短（{len(text)}<{MIN_TEXT_LEN} 字，疑似纯晒图无内容）")
    # 可体验性：必须有可点开的外链（http/https），否则没东西可以去用/去看
    if REQUIRE_SOURCE_URL and not _is_http_url(source_url):
        reasons.append("无可体验外链（source_url 缺失或非 http/https）")

    return {
        "passed": not reasons,
        "reasons": reasons,
        "metrics": {
            "likes": likes,
            "collects": collects,
            "comments": comments,
            "shares": shares,
            "save_rate": save_rate,
            "text_len": len(text),
            "media_count": len(media),
        },
    }
