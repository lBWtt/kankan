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
import sys
from datetime import datetime, timezone
from typing import Dict, List, Optional

from collection_standard import parse_count  # 同目录，脚本运行时 scrape/ 在 sys.path

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
    }


MAPPERS = {"xhs": map_xhs, "dy": map_dy}


def _read_jsonl_files(mc_dir: str, platform: str):
    """读 MediaCrawler 的内容 jsonl：data/{存储目录}/jsonl/*_contents_*.jsonl。返回 (rows, files)。"""
    store_dir = PLATFORM_STORE_DIR.get(platform, platform)
    pattern = os.path.join(mc_dir, "data", store_dir, "jsonl", "*_contents_*.jsonl")
    files = sorted(glob.glob(pattern))
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


def main() -> int:
    ap = argparse.ArgumentParser(description="MediaCrawler jsonl → 管线 collect 标准 JSON")
    ap.add_argument("--dir", default="F:/MediaCrawler", help="MediaCrawler 根目录（含 data/）")
    ap.add_argument("--platform", choices=list(MAPPERS.keys()), default="xhs", help="xhs 小红书 / dy 抖音")
    ap.add_argument("-o", "--out", default=None, help="输出 JSON 文件路径（默认 items_{platform}.json）")
    args = ap.parse_args()

    mapper = MAPPERS[args.platform]
    rows, files = _read_jsonl_files(args.dir, args.platform)
    if not files:
        print(f"没找到 jsonl：{args.dir}/data/{args.platform}/jsonl/*_contents_*.jsonl\n"
              f"先在 MediaCrawler 里把 SAVE_DATA_OPTION 设成 jsonl 再抓。", file=sys.stderr)
        return 1

    items, seen = [], set()
    for row in rows:
        item = mapper(row)
        if not item:
            continue
        if item["source_url"] in seen:
            continue
        seen.add(item["source_url"])
        items.append(item)

    out = args.out or f"items_{args.platform}.json"
    with open(out, "w", encoding="utf-8") as f:
        json.dump(items, f, ensure_ascii=False, indent=2)
    print(f"读 {len(files)} 个 jsonl、{len(rows)} 行 → 转出 {len(items)} 条标准条目 → {out}")
    print(f"下一步：python -m app.pipeline collect {out} --platform {PLATFORM_SOURCE_NAME[args.platform]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
