# ============================================================
# 这个文件是干什么的：把 MediaCrawler 抓的 jsonl（小红书/抖音）转成本管线 collect 命令
#   吃的「标准条目」JSON 数组（形状见 app/services/ingestion.py 文件头）。
# 它对应产品里的什么功能：② 采集接口——MediaCrawler 采集 → 本适配器转格式 → pipeline collect 入候选池。
# 如果它出错了：转不出/字段错位 → collect 入池失败或字段乱；对齐 ingestion 文件头的标准形状即可。
#
# 用法（在 backend/ 下）：
#   1) 先用 MediaCrawler 抓（在 F:/MediaCrawler，配好 config：PLATFORM/KEYWORDS/登录，SAVE_DATA_OPTION=jsonl）
#        python main.py            # 产出 data/{xhs,dy}/jsonl/search_contents_YYYY-MM-DD.jsonl
#   2) 转格式：
#        python scrape/mediacrawler_adapter.py --dir F:/MediaCrawler --platform xhs -o items_xhs.json
#   3) 入候选池 → AI 富化 → 审核：
#        python -m app.pipeline collect items_xhs.json --platform xiaohongshu
#        AI_PROVIDER=deepseek DEEPSEEK_API_KEY=sk-xxx python -m app.pipeline process
#
# 注意（媒体转存）：小红书/抖音的图/视频是它们 CDN 的链接，多有防盗链，App 直接显示可能挂。
#   生产要在「approve→建项目」时把媒体**下载转存到本地/OSS**（见 PIPELINE_PLAN 决策4/媒体转存）。
#   本适配器先把原始 URL 透传进候选池，转存是下一步。
# ============================================================
import argparse
import glob
import json
import os
import re
import sys
from datetime import datetime, timezone
from typing import Dict, List, Optional

from collection_standard import evaluate, parse_count  # 同目录，脚本运行时 scrape/ 在 sys.path


# 宪法 9.0：搜个人做出来的成果，不以泛词 AI 命中。
OUTCOME_RE = re.compile(
    r"我(?:用|拿|让).{0,12}(?:做|搓|写|搭|开发)|我做了|做了个|做了一个|"
    r"一个人做|独立开发|周末做|我.{0,20}(?:上线|发布|开源)了|做出来",
    re.I,
)
FORMAT_RE = re.compile(r"vibe\s*cod(?:ing|ed)\s*大赏", re.I)
ARTIFACT_RE = re.compile(
    r"原型|播放器|生成器|小工具|工具|小游戏|游戏|网站|网页|小程序|app|"
    r"插件|机器人|可视化|星系|系统|产品|手势|自习室",
    re.I,
)
MATERIAL_RE = re.compile(
    r"教程|入门|课程|保姆级|怎么用|如何使用|提示词合集|新闻|融资|发布会|"
    r"盘点|周报|日报|快讯|观点|测评|接单|变现|副业|资料包|训练营|"
    r"全流程|安装|学习计划|加入我们|必备技能|轻松学会|如何|怎么用|方法|技巧",
    re.I,
)

# MediaCrawler 的 PLATFORM 目录名 → 我们候选池里的 source_platform 友好名
PLATFORM_SOURCE_NAME = {
    "xhs": "xiaohongshu",
    "dy": "douyin",
}

# MediaCrawler 存数据的目录名：xhs 用缩写 "xhs"，但抖音用全名 "douyin"（不是 config 的 "dy"）——
# 两边不一致，这里显式映射，否则 --platform dy 会去空的 data/dy/ 找不到文件。
PLATFORM_STORE_DIR = {
    "xhs": "xhs",
    "dy": "douyin",
}


def _ms_to_iso(ts) -> Optional[str]:
    """时间戳 → ISO 字符串（发布时间，供时效判断/排序）。兼容毫秒（小红书，13位）
    和秒（抖音 create_time，10位）：>1e12 视为毫秒。拿不到就 None。"""
    try:
        n = int(ts)
    except (TypeError, ValueError):
        return None
    try:
        return datetime.fromtimestamp(n / 1000 if n > 1_000_000_000_000 else n,
                                      tz=timezone.utc).isoformat()
    except (ValueError, OSError):
        return None


def _engagement(row: Dict, likes_key: str, collects_key: str) -> dict:
    """抽取互动数（原始串照传，parse_count 在标准里统一解析'10万+'这类）。"""
    return {
        "likes": parse_count(row.get(likes_key)),
        "collects": parse_count(row.get(collects_key)),
        "comments": parse_count(row.get("comment_count")),
        "shares": parse_count(row.get("share_count")),
    }


def _split_urls(value) -> List[str]:
    """MediaCrawler 把多图/多视频存成逗号分隔字符串 → 拆成列表（去空去重保序）。"""
    if not value:
        return []
    out, seen = [], set()
    for u in str(value).split(","):
        u = u.strip()
        if u and u not in seen:
            seen.add(u)
            out.append(u)
    return out


def _media(images: List[str], videos: List[str]) -> List[dict]:
    return (
        [{"url": u, "media_type": "image"} for u in images]
        + [{"url": u, "media_type": "video"} for u in videos]
    )


def map_xhs(row: Dict) -> Optional[dict]:
    url = (row.get("note_url") or "").strip()
    desc = row.get("desc") or ""
    title = (row.get("title") or "").strip() or desc.strip()[:40]
    if not url or not title:
        return None
    return {
        "source_url": url,
        "title": title,
        "text": desc,
        "source_platform": "xiaohongshu",
        "original_author_name": row.get("nickname") or None,  # 该版 MediaCrawler 已脱敏
        "media": _media(_split_urls(row.get("image_list")), _split_urls(row.get("video_url"))),
        "engagement": _engagement(row, "liked_count", "collected_count"),
        "published_at": _ms_to_iso(row.get("time")),
        "requires_manual_experience_url": True,
    }


def map_dy(row: Dict) -> Optional[dict]:
    url = (row.get("aweme_url") or "").strip()
    desc = row.get("desc") or ""
    title = (row.get("title") or "").strip() or desc.strip()[:40]
    if not url or not title:
        return None
    # 抖音媒体字段：图文用 note_download_url，视频用 **video_download_url**（不是 video_url），
    # 封面在 cover_url。视频没图，把封面当第一张图 → 有封面可展示、也让 approve 转存能出封面。
    images = _split_urls(row.get("note_download_url"))
    cover = (row.get("cover_url") or "").strip()
    if cover and cover not in images:
        images = [cover] + images
    videos = _split_urls(row.get("video_download_url"))
    return {
        "source_url": url,
        "title": title,
        "text": desc,
        "source_platform": "douyin",
        "original_author_name": row.get("nickname") or None,
        "media": _media(images, videos),
        # 抖音 store 已把 digg_count→liked_count、collect_count→collected_count（与小红书同名）
        "engagement": _engagement(row, "liked_count", "collected_count"),
        "published_at": _ms_to_iso(row.get("create_time") or row.get("time")),
        "requires_manual_experience_url": True,
    }


MAPPERS = {"xhs": map_xhs, "dy": map_dy}


def _read_jsonl_files(mc_dir: str, platform: str):
    """读 MediaCrawler 的内容 jsonl：data/{存储目录}/jsonl/*_contents_*.jsonl。返回 (rows, files)。"""
    store_dir = PLATFORM_STORE_DIR.get(platform, platform)
    patterns = [
        os.path.join(mc_dir, "data", store_dir, "jsonl", "*_contents_*.jsonl"),
        os.path.join(mc_dir, store_dir, "jsonl", "*_contents_*.jsonl"),
        os.path.join(mc_dir, "**", f"*{store_dir}*contents*.jsonl"),
        os.path.join(mc_dir, "**", "*_contents_*.jsonl"),
    ]
    files = []
    for pattern in patterns:
        matches = sorted(glob.glob(pattern, recursive=True))
        if matches:
            files = matches
            break
    rows: List[Dict] = []
    for fp in files:
        with open(fp, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    rows.append(json.loads(line))
                except json.JSONDecodeError:
                    continue
    return rows, files


def _constitution_result(item: dict) -> tuple[bool, List[str]]:
    blob = f"{item.get('title') or ''}\n{item.get('text') or ''}"
    headline = (item.get("title") or "")[:160]
    reasons: List[str] = []
    if not (OUTCOME_RE.search(blob) or (
        FORMAT_RE.search(headline) and ARTIFACT_RE.search(headline)
    )):
        reasons.append("not_outcome_intent")
    if MATERIAL_RE.search(blob):
        reasons.append("tutorial_or_material")
    standard = evaluate(item, item.get("source_platform"))
    if not standard["passed"]:
        reasons.extend(["mechanical_gate:" + reason for reason in standard["reasons"]])
    return not reasons, reasons


def main() -> int:
    ap = argparse.ArgumentParser(description="MediaCrawler jsonl → 管线 collect 标准 JSON")
    ap.add_argument("--dir", default="F:/MediaCrawler", help="MediaCrawler 根目录（含 data/）")
    ap.add_argument("--platform", choices=list(MAPPERS.keys()), default="xhs", help="xhs 小红书 / dy 抖音")
    ap.add_argument("-o", "--out", default=None, help="输出 JSON 文件路径（默认 items_{platform}.json）")
    ap.add_argument("--constitution", action="store_true",
                    help="按宪法 9.0 粗筛：成果意图、非教程、有 proof、高互动")
    args = ap.parse_args()

    mapper = MAPPERS[args.platform]
    rows, files = _read_jsonl_files(args.dir, args.platform)
    if not files:
        print(f"没找到 jsonl：{args.dir}/data/{args.platform}/jsonl/*_contents_*.jsonl\n"
              f"先在 MediaCrawler 里把 SAVE_DATA_OPTION 设成 jsonl 再抓。", file=sys.stderr)
        return 1

    items, seen = [], set()
    rejected: Dict[str, int] = {}
    for row in rows:
        item = mapper(row)
        if not item:
            continue
        if item["source_url"] in seen:
            continue
        if args.constitution:
            passed, reasons = _constitution_result(item)
            if not passed:
                for reason in reasons:
                    key = reason.split(":", 1)[0]
                    rejected[key] = rejected.get(key, 0) + 1
                continue
        seen.add(item["source_url"])
        items.append(item)

    out = args.out or f"items_{args.platform}.json"
    with open(out, "w", encoding="utf-8") as f:
        json.dump(items, f, ensure_ascii=False, indent=2)
    print(f"读 {len(files)} 个 jsonl、{len(rows)} 行 → 转出 {len(items)} 条标准条目 → {out}")
    if args.constitution:
        print("宪法粗筛拦截：" + json.dumps(rejected, ensure_ascii=False, sort_keys=True))
    print(f"下一步：python -m app.pipeline collect {out} --platform {PLATFORM_SOURCE_NAME[args.platform]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
