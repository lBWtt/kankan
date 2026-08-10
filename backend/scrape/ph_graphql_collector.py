# ============================================================
# 这个文件是干什么的：Product Hunt 榜单采集器（GraphQL API 版）——拿"最近高票"的精品产品
#   （≈ 周榜/月榜），带真实产品链接 + 产品截图画廊(多图) + makers(创作者)，转成本管线标准条目。
#   比 RSS 版(ph_collector.py，只给近期 feed)质量高：order:VOTES + 时间窗 = 榜单。
# 为什么用 GraphQL：PH 榜单页是 JS SPA，静态和无头浏览器都抓不动（反爬）；GraphQL 是唯一干净路子。
#
# 鉴权（token 只内联传，别写进任何文件）：用 API Key+Secret 走 client_credentials 换 access_token。
#   PH 后台 https://www.producthunt.com/v2/oauth/applications 建 application 拿 Key/Secret。
#
# 用法（backend/ 下）：
#   PH_KEY=xxx PH_SECRET=yyy python scrape/ph_graphql_collector.py -o items_phg.json --limit 30 --days 30
#   python -m app.pipeline collect items_phg.json --platform producthunt
#   AI_PROVIDER=deepseek DEEPSEEK_API_KEY=sk-xxx python -m app.pipeline process
#   → 人工审 → 发布。（发现的 makers 会以 proposed 追加进 sources.yaml。）
# ============================================================
from __future__ import annotations

import argparse
import datetime
import json
import os
import sys
import urllib.request

from collector_covers import gather_media

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

OAUTH = "https://api.producthunt.com/v2/oauth/token"
GQL = "https://api.producthunt.com/v2/api/graphql"
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) kankan-ph-gql/1.0"


def _access_token() -> str | None:
    key, secret = os.environ.get("PH_KEY"), os.environ.get("PH_SECRET")
    if not (key and secret):
        print("缺 PH_KEY / PH_SECRET 环境变量（内联传）", file=sys.stderr)
        return None
    body = json.dumps({"client_id": key, "client_secret": secret,
                       "grant_type": "client_credentials"}).encode()
    try:
        req = urllib.request.Request(OAUTH, data=body, method="POST",
                                     headers={"Content-Type": "application/json", "Accept": "application/json"})
        return json.load(urllib.request.urlopen(req, timeout=30)).get("access_token")
    except Exception as e:
        print("换 token 失败：", repr(e)[:160], file=sys.stderr)
        return None


def _graphql(token: str, query: str) -> dict:
    req = urllib.request.Request(GQL, data=json.dumps({"query": query}).encode(), method="POST",
                                 headers={"Authorization": "Bearer " + token,
                                          "Content-Type": "application/json", "Accept": "application/json"})
    return json.load(urllib.request.urlopen(req, timeout=40))


def _resolve(url: str, timeout: int = 10) -> str:
    """PH 的 website 是 producthunt.com/r/CODE 跳转 → 跟到真实产品地址。"""
    try:
        req = urllib.request.Request(url, headers={"User-Agent": UA})
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.geturl() or url
    except Exception:
        return url


def collect(token: str, limit: int, days: int, max_makers: int = 4):
    after = (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=days)).strftime("%Y-%m-%dT00:00:00Z")
    query = f'''{{ posts(order: VOTES, postedAfter: "{after}", first: {min(limit, 40)}) {{
      edges {{ node {{ name tagline description votesCount commentsCount website url
        thumbnail {{ url }} media {{ url }} makers {{ name username }}
        topics {{ edges {{ node {{ name }} }} }} }} }} }} }}'''
    d = _graphql(token, query)
    if "errors" in d:
        print("GraphQL errors：", d["errors"][:2], file=sys.stderr)
        return [], []
    edges = d.get("data", {}).get("posts", {}).get("edges", [])
    print(f"PH 榜单：拉到 {len(edges)} 条（近 {days} 天 top-by-votes），深挖…")

    items, makers = [], {}
    for e in edges:
        n = e["node"]
        # 广告过滤：maker 一大堆 = 公司级 SaaS 在打广告（Pazi/Tencent 那种），不是"个人做的有意思的东西"。
        # 只留 maker ≤ max_makers 的（个人/小团队），更对味、图也更像真截图而非营销banner。
        if len(n.get("makers") or []) > max_makers:
            continue
        product = _resolve(n["website"]) if n.get("website") else None
        if not product or "producthunt.com" in product:
            continue  # 解析不到真实产品链接就跳（不拿 PH 页当去用入口）
        gallery = [m["url"] for m in (n.get("media") or []) if m.get("url")]
        thumb = (n.get("thumbnail") or {}).get("url")
        extra = ([thumb] if thumb else []) + gallery       # PH 缩略图 + 产品画廊截图（多图，质量高）
        media = gather_media(product, 4, extra=extra)
        if not media:
            continue  # proof 缺失不收，禁止 mShots/官网截图兜底
        desc = " ".join(filter(None, [n.get("tagline"), n.get("description")]))
        item = {
            "source_url": n.get("url") or product,   # PH 永久链接做去重键
            "title": (n.get("name") or "")[:80],
            "text": desc[:2000],
            "source_platform": "producthunt",
            "content_kind": "project",
            "try_url": product,
            "language": "en-US",
            "engagement": {"likes": n.get("votesCount") or 0, "comments": n.get("commentsCount") or 0},
            "media": media,
        }
        mk = (n.get("makers") or [])
        if mk:
            item["original_author_name"] = mk[0].get("name") or mk[0].get("username")
            item["original_author_url"] = f"https://www.producthunt.com/@{mk[0].get('username')}"
            for m in mk:
                u = m.get("username")
                if u:
                    makers[u] = m.get("name") or u
        items.append(item)
    print(f"产出 {len(items)} 条（{sum(1 for it in items if it.get('media'))} 有封面），见到 makers {len(makers)} 位。")
    return items, makers


def _register_makers(makers: dict):
    """把见到的 makers 以 proposed 追加进 sources.yaml（去重），供将来收录创作者。"""
    if not makers:
        return
    try:
        from pathlib import Path
        from ruamel.yaml import YAML
        yaml = YAML()
        path = Path(__file__).with_name("sources.yaml")
        doc = yaml.load(open(path, encoding="utf-8"))
        have = {str(s.get("handle") or s.get("url") or "").lower() for s in doc.get("sources", [])}
        added = 0
        for u, name in makers.items():
            url = f"https://www.producthunt.com/@{u}"
            if url.lower() in have or u.lower() in have:
                continue
            doc["sources"].append({
                "name": f"PH maker @{u}（{name}）", "kind": "directory", "url": url,
                "lang": "en", "focus": "indie-products", "region_hint": "global",
                "status": "proposed", "found_by": "ph_makers",
            })
            added += 1
        if added:
            import io
            buf = io.StringIO(); yaml.dump(doc, buf); path.write_text(buf.getvalue(), encoding="utf-8")
        print(f"sources.yaml：新增 {added} 位 PH maker（proposed）。")
    except Exception as e:
        print("登记 makers 跳过：", repr(e)[:120], file=sys.stderr)


def main() -> int:
    ap = argparse.ArgumentParser(description="Product Hunt 榜单采集器（GraphQL）")
    ap.add_argument("-o", "--out", default="items_phg.json")
    ap.add_argument("--limit", type=int, default=30)
    ap.add_argument("--days", type=int, default=30, help="时间窗（近 N 天 top-by-votes ≈ 月榜/周榜）")
    ap.add_argument("--max-makers", type=int, default=4, help="maker 上限：超过=公司级 SaaS(广告)，跳过；留个人/小团队")
    ap.add_argument("--no-makers", action="store_true", help="不把 makers 登记进 sources.yaml")
    args = ap.parse_args()
    token = _access_token()
    if not token:
        return 1
    items, makers = collect(token, args.limit, args.days, args.max_makers)
    if not items:
        return 1
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(items, f, ensure_ascii=False, indent=2)
    if not args.no_makers:
        _register_makers(makers)
    print(f"写出 {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
