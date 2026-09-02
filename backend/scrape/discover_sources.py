# ============================================================
# 这个文件是干什么的：内容源登记册 `sources.yaml` 的**管理 + 自动发现** CLI。
#   把"自己去找到同类博主/网站并存起来"这件事固化成命令，换任何 AI 跑都一样。
# 它对应产品里的什么功能：内容源治理——采集器只从 confirmed 源拉；本工具负责
#   登记(add)/确认(promote)/否掉(reject)/看(list)/自动提名(discover)。
# 用法（backend/ 下）：
#   python scrape/discover_sources.py list [--status proposed]
#   python scrape/discover_sources.py add --kind x_account --handle someone --name "@someone" --focus indie-products
#   python scrape/discover_sources.py add --kind website --url https://foo.com --name Foo
#   python scrape/discover_sources.py promote levelsio        # proposed → confirmed（名/handle/url 任一匹配）
#   python scrape/discover_sources.py reject tudingai
#   python scrape/discover_sources.py discover [--min-hits 2] [--dry-run]
#     ↑ 行为发现：扫已采候选里"带可用链接"的原作者，高频者提名为新源(proposed)。
#
# 说明：站类的"跑搜索发现新源"那半，是 **agent 用自己的联网搜索**跑 `sources.yaml` 里
#   discovery_hints.site_queries，把结果 add 成 proposed（脚本没法替代优质网搜）。X 号那半
#   既可 agent 搜、也可本命令的 discover（行为）自动提名。真去 X 抓仍需 CDP（见 memory）。
# ============================================================
from __future__ import annotations

import argparse
import io
import os
import sys
from pathlib import Path
from urllib.parse import urlparse

# 直接跑 scrape/ 下脚本时，把 backend/ 加进 path，好让 discover 能 import app（同 pipeline_run 约定）。
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from ruamel.yaml import YAML

SOURCES_PATH = Path(__file__).with_name("sources.yaml")
yaml = YAML()
yaml.preserve_quotes = True
yaml.indent(mapping=2, sequence=2, offset=0)

try:  # GBK 控制台下也能打印中文/符号
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass


def _load():
    with open(SOURCES_PATH, encoding="utf-8") as f:
        return yaml.load(f)


def _dump(doc) -> None:
    buf = io.StringIO()
    yaml.dump(doc, buf)
    SOURCES_PATH.write_text(buf.getvalue(), encoding="utf-8")


def _key(src: dict) -> str:
    """源的去重键：x_account 用 handle，其余用 url 的 host+path。"""
    if src.get("handle"):
        return "x:" + str(src["handle"]).lower().lstrip("@")
    u = str(src.get("url") or "").strip().lower().rstrip("/")
    p = urlparse(u)
    return "w:" + (p.netloc + p.path if p.netloc else u)


def _existing_keys(doc) -> set:
    return {_key(s) for s in doc.get("sources", [])}


def _match(src: dict, needle: str) -> bool:
    n = needle.lower().lstrip("@")
    return n in str(src.get("name", "")).lower() \
        or n == str(src.get("handle", "")).lower().lstrip("@") \
        or n in str(src.get("url", "")).lower()


# ---------- 命令 ----------

def cmd_list(args) -> int:
    doc = _load()
    for s in doc.get("sources", []):
        if args.status and s.get("status") != args.status:
            continue
        loc = s.get("handle") and ("@" + s["handle"]) or s.get("url", "")
        print(f"  [{s.get('status','?'):9}] {s.get('kind',''):12} {s.get('name','')}  —  {loc}")
    return 0


def cmd_add(args) -> int:
    doc = _load()
    if args.kind == "x_account" and not args.handle:
        print("x_account 需要 --handle"); return 2
    if args.kind != "x_account" and not args.url:
        print("站类需要 --url"); return 2
    new = {
        "name": args.name or (("@" + args.handle) if args.handle else args.url),
        "kind": args.kind,
        **({"handle": args.handle.lstrip("@")} if args.handle else {"url": args.url}),
        "lang": args.lang,
        "focus": args.focus,
        "region_hint": args.region,
        "status": args.status,
        "found_by": args.found_by,
    }
    if _key(new) in _existing_keys(doc):
        print(f"已存在，跳过：{new['name']}"); return 0
    doc["sources"].append(new)
    _dump(doc)
    print(f"已登记（{args.status}）：{new['name']}")
    return 0


def _set_status(args, target: str) -> int:
    doc = _load()
    hit = [s for s in doc.get("sources", []) if _match(s, args.needle)]
    if not hit:
        print(f"没匹配到：{args.needle}"); return 1
    if len(hit) > 1:
        print("匹配到多个，请更精确：", [s["name"] for s in hit]); return 1
    hit[0]["status"] = target
    _dump(doc)
    print(f"{hit[0]['name']} → {target}")
    return 0


def cmd_promote(args) -> int:
    return _set_status(args, "confirmed")


def cmd_reject(args) -> int:
    return _set_status(args, "rejected")


def cmd_discover(args) -> int:
    """行为发现：从已采候选里，按'带可用链接的项目贴'的原作者高频提名新源。"""
    # 延迟导入 app（只有 discover 用 DB），避免 list/add 也要起 DB。
    from sqlalchemy import select
    from app.core.db import SessionLocal
    from app.models import CandidateContent

    doc = _load()
    existing = _existing_keys(doc)
    tally: dict[str, dict] = {}
    with SessionLocal() as db:
        rows = db.scalars(
            select(CandidateContent).where(CandidateContent.original_author_url.isnot(None))
        ).all()
    for c in rows:
        # "带可用链接" = 有 try_url，或 raw_json.known_try_url
        has_link = bool(c.try_url) or bool((c.raw_json or {}).get("known_try_url"))
        if not has_link:
            continue
        url = (c.original_author_url or "").strip()
        if not url:
            continue
        p = urlparse(url if "//" in url else "https://" + url)
        host = p.netloc.lower()
        is_x = "twitter.com" in host or "x.com" in host
        handle = p.path.strip("/").split("/")[0] if is_x else ""
        key = ("x:" + handle.lower()) if is_x else ("w:" + host + p.path.rstrip("/"))
        t = tally.setdefault(key, {
            "hits": 0, "is_x": is_x, "handle": handle, "url": url,
            "name": (("@" + handle) if is_x else host), "platform": c.source_platform,
        })
        t["hits"] += 1

    proposals = [t for k, t in tally.items() if t["hits"] >= args.min_hits and k not in existing]
    proposals.sort(key=lambda x: -x["hits"])
    if not proposals:
        print(f"没有达到 {args.min_hits} 次命中的新作者可提名（现有源已覆盖或数据不足）。")
        return 0
    print(f"行为发现 {len(proposals)} 个候选源（命中≥{args.min_hits}）：")
    for t in proposals:
        print(f"  {t['hits']:>3}× {'X ' if t['is_x'] else '站'} {t['name']}  ({t['url']})")
    if args.dry_run:
        print("（--dry-run，未写入。去掉即写为 proposed）")
        return 0
    for t in proposals:
        doc["sources"].append({
            "name": t["name"],
            "kind": "x_account" if t["is_x"] else "website",
            **({"handle": t["handle"]} if t["is_x"] else {"url": t["url"]}),
            "lang": "zh", "focus": "mixed", "region_hint": "global",
            "scrapable": "x_timeline" if t["is_x"] else "html",
            "status": "proposed", "found_by": "behavior",
            "note": f"行为发现：{t['hits']} 条带可用链接的项目贴",
        })
    _dump(doc)
    print(f"已写入 {len(proposals)} 个 proposed（去 list 看、promote 确认）。")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description="内容源登记册管理 + 自动发现")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("list", help="列出登记册")
    p.add_argument("--status", help="只看某状态 seed/confirmed/proposed/rejected")
    p.set_defaults(func=cmd_list)

    p = sub.add_parser("add", help="登记一个源（默认 confirmed）")
    p.add_argument("--kind", required=True,
                   choices=["website", "directory", "awesome_list", "newsletter", "x_account"])
    p.add_argument("--name")
    p.add_argument("--url")
    p.add_argument("--handle")
    p.add_argument("--lang", default="zh")
    p.add_argument("--focus", default="mixed")
    p.add_argument("--region", default="global")
    p.add_argument("--status", default="confirmed")
    p.add_argument("--found-by", dest="found_by", default="manual")
    p.set_defaults(func=cmd_add)

    p = sub.add_parser("promote", help="proposed → confirmed")
    p.add_argument("needle", help="名/handle/url 任一片段")
    p.set_defaults(func=cmd_promote)

    p = sub.add_parser("reject", help="→ rejected")
    p.add_argument("needle")
    p.set_defaults(func=cmd_reject)

    p = sub.add_parser("discover", help="行为发现：按带链接项目贴的高频原作者提名新源")
    p.add_argument("--min-hits", type=int, default=2)
    p.add_argument("--dry-run", action="store_true")
    p.set_defaults(func=cmd_discover)

    args = ap.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
