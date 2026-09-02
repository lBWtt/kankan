"""抖音多通道自动发现器。

只负责扩大召回并调用既有 Python 机械粗筛，不做人工选品：
1. 站内成果意图词/话题词；2. 搜索引擎公开索引补漏；
3. 已知优秀视频详情回查；4. 可选优秀作者作品链。

输出仍是 mediacrawler_adapter.py 的标准 item，后续统一交给 DeepSeek。
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path


DEFAULT_QUERIES = [
    "vibecoding",
    "vibecoding大赏",
    "我做了个网站",
    "我做了个应用",
    "我做了个游戏",
    "我做了个工具",
    "独立开发上线",
    "个人开发作品",
    "做了一个小程序",
    "上线了一个网站",
    "把数据做成可视化",
    "用代码做了一个",
]

INDEX_QUERIES = [
    "vibecoding 作品",
    "vibecoding大赏 作品",
    "独立开发 上线 作品",
    "我做了个 网站 工具",
    "我做了个 游戏 应用",
    "个人开发 小程序 上线",
]

DOUYIN_VIDEO_RE = re.compile(r"https?://(?:www\.)?douyin\.com/video/(\d+)", re.I)


def _run(command: list[str], cwd: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, cwd=str(cwd), text=True, encoding="utf-8", errors="replace")


def _read_urls(path: Path | None) -> list[str]:
    if not path or not path.exists():
        return []
    urls: list[str] = []
    if path.suffix.lower() == ".json":
        data = json.loads(path.read_text(encoding="utf-8-sig"))
        for row in data if isinstance(data, list) else []:
            url = row.get("source_url") if isinstance(row, dict) else None
            if url:
                urls.append(url)
    else:
        urls.extend(line.strip() for line in path.read_text(encoding="utf-8-sig").splitlines())
    return list(dict.fromkeys(u for u in urls if DOUYIN_VIDEO_RE.search(u)))


def _index_urls(queries: list[str], per_query: int = 30) -> tuple[list[str], dict]:
    found: list[str] = []
    report: dict[str, int] = {}
    headers = {"User-Agent": "Mozilla/5.0 KankanDiscovery/1.0"}
    for query in queries:
        q = f"site:douyin.com/video {query}"
        url = "https://www.bing.com/search?format=rss&q=" + urllib.parse.quote(q)
        count = 0
        try:
            req = urllib.request.Request(url, headers=headers)
            with urllib.request.urlopen(req, timeout=20) as response:
                root = ET.fromstring(response.read())
            for item in root.findall("./channel/item"):
                blob = " ".join((item.findtext("link") or "", item.findtext("description") or ""))
                for match in DOUYIN_VIDEO_RE.finditer(blob):
                    found.append(f"https://www.douyin.com/video/{match.group(1)}")
                    count += 1
                    if count >= per_query:
                        break
                if count >= per_query:
                    break
        except Exception:
            count = 0
        report[query] = count
    return list(dict.fromkeys(found)), report


def main() -> int:
    ap = argparse.ArgumentParser(description="抖音多通道发现 → Python机械粗筛 → 标准item")
    ap.add_argument("--mc-root", default="F:/MediaCrawler")
    ap.add_argument("--mc-python", default="D:/conda/envs/mediacrawler/python.exe")
    ap.add_argument("--work-dir", required=True, help="本轮隔离输出目录")
    ap.add_argument("--out", required=True, help="机械粗筛后的标准 JSON")
    ap.add_argument("--search-limit", type=int, default=100, help="每个站内成果词最多召回数")
    ap.add_argument("--queries", default=",".join(DEFAULT_QUERIES))
    ap.add_argument("--seed-file", type=Path, help="历史优秀标准item JSON或每行一个抖音视频URL")
    ap.add_argument("--creator-file", type=Path, help="每行一个优秀作者主页URL，可选")
    ap.add_argument("--headless", choices=["yes", "no"], default="yes")
    args = ap.parse_args()

    mc_root = Path(args.mc_root)
    work_dir = Path(args.work_dir).resolve()
    work_dir.mkdir(parents=True, exist_ok=True)
    queries = list(dict.fromkeys(q.strip() for q in args.queries.split(",") if q.strip()))
    stats: dict = {"started_at": datetime.now(timezone.utc).isoformat(), "queries": queries}

    search_cmd = [
        args.mc_python, "main.py", "--platform", "dy", "--type", "search", "--lt", "qrcode",
        "--keywords", ",".join(queries), "--crawler_max_notes_count", str(args.search_limit),
        "--save_data_option", "jsonl", "--save_data_path", str(work_dir),
        "--get_comment", "no", "--get_sub_comment", "no", "--headless", args.headless,
        "--max_concurrency_num", "1",
    ]
    stats["station_search_exit"] = _run(search_cmd, mc_root).returncode

    index_urls, index_counts = _index_urls(INDEX_QUERIES)
    seed_urls = _read_urls(args.seed_file)
    detail_urls = list(dict.fromkeys(index_urls + seed_urls))
    stats["external_index"] = index_counts
    stats["external_index_unique_urls"] = len(index_urls)
    stats["seed_urls"] = len(seed_urls)
    if detail_urls:
        detail_cmd = [
            args.mc_python, "main.py", "--platform", "dy", "--type", "detail", "--lt", "qrcode",
            "--specified_id", ",".join(detail_urls), "--save_data_option", "jsonl",
            "--save_data_path", str(work_dir), "--get_comment", "no", "--get_sub_comment", "no",
            "--headless", args.headless, "--max_concurrency_num", "1",
        ]
        stats["detail_exit"] = _run(detail_cmd, mc_root).returncode

    creator_urls = []
    if args.creator_file and args.creator_file.exists():
        creator_urls = [u.strip() for u in args.creator_file.read_text(encoding="utf-8-sig").splitlines() if u.strip()]
    stats["creator_urls"] = len(creator_urls)
    if creator_urls:
        creator_cmd = [
            args.mc_python, "main.py", "--platform", "dy", "--type", "creator", "--lt", "qrcode",
            "--creator_id", ",".join(creator_urls), "--save_data_option", "jsonl",
            "--save_data_path", str(work_dir), "--get_comment", "no", "--get_sub_comment", "no",
            "--headless", args.headless, "--max_concurrency_num", "1",
        ]
        stats["creator_exit"] = _run(creator_cmd, mc_root).returncode

    adapter = Path(__file__).with_name("mediacrawler_adapter.py")
    adapt_cmd = [sys.executable, str(adapter), "--dir", str(work_dir), "--platform", "dy", "--discovery", "-o", str(Path(args.out).resolve())]
    adapted = _run(adapt_cmd, Path.cwd())
    # 某轮所有通道均为空不是程序错误；仍产出空标准数组，便于调度器继续下一轮。
    if adapted.returncode and "没找到 jsonl" in ((adapted.stdout or "") + (adapted.stderr or "")):
        Path(args.out).resolve().write_text("[]\n", encoding="utf-8")
        stats["adapter_exit"] = 0
        stats["empty_round"] = True
    else:
        stats["adapter_exit"] = adapted.returncode
    stats["finished_at"] = datetime.now(timezone.utc).isoformat()
    stats["channels"] = Counter({
        "station_search": len(queries),
        "external_index": len(index_urls),
        "seed_detail": len(seed_urls),
        "creator_chain": len(creator_urls),
    })
    audit_path = work_dir / "discovery_audit.json"
    audit_path.write_text(json.dumps(stats, ensure_ascii=False, indent=2, default=dict), encoding="utf-8")
    print(json.dumps(stats, ensure_ascii=False, indent=2, default=dict))
    return stats["adapter_exit"]


if __name__ == "__main__":
    raise SystemExit(main())
