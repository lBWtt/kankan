# ============================================================
# 这个文件是干什么的：按采集标准（collection_standard.py）对 adapter 产出的标准条目做**机械粗筛**，
#   输出"够格进池"的子集 + 一份**可审计报告**（每条 PASS/DROP + 原因 + 热度指标），
#   让人一眼看清"留下来的凭什么留、砍掉的凭什么砍"。
# 它对应产品里的什么功能：② 采集漏斗的第一道闸（adapter → **prefilter** → collect → DeepSeek → 审核）。
#
# 用法（在 backend/ 下）：
#   python scrape/prefilter.py --in items_xhs.json --platform xiaohongshu -o items_xhs_passed.json
# 然后只把通过的入池：
#   python -m app.pipeline collect items_xhs_passed.json --platform xiaohongshu
# ============================================================
import argparse
import json
import sys
from typing import List

from collection_standard import (
    MIN_TEXT_LEN,
    REQUIRE_MEDIA,
    REQUIRE_SOURCE_URL,
    evaluate,
    thresholds_for,
)


def _fmt(n) -> str:
    return "-" if n is None else str(n)


def run(items: List[dict], platform: str) -> tuple:
    """评估全部条目。返回 (passed_items, report_lines, summary)。
    报告与输出按**收藏数**降序（热度信号；收藏率仅作参考不再当红线）——让"谁凭什么留在前面"一眼可读。"""
    evaluated = [(item, evaluate(item, platform)) for item in items]
    evaluated.sort(key=lambda x: (x[1]["metrics"]["collects"] or -1), reverse=True)

    report, passed = [], []
    drop_reasons: dict = {}
    for item, r in evaluated:
        m = r["metrics"]
        title = (item.get("title") or "")[:24]
        mark = "PASS" if r["passed"] else "DROP"
        why = "" if r["passed"] else "  ← " + "；".join(r["reasons"])
        report.append(
            f"[{mark}] 收藏率 {_fmt(m['save_rate']):>5} | 收藏 {_fmt(m['collects']):>7} "
            f"点赞 {_fmt(m['likes']):>7} | {title}{why}"
        )
        if r["passed"]:
            passed.append(item)
        else:
            for reason in r["reasons"]:
                drop_reasons[reason.split("（")[0]] = (
                    drop_reasons.get(reason.split("（")[0], 0) + 1
                )
    summary = {
        "in": len(items),
        "passed": len(passed),
        "dropped": len(items) - len(passed),
        "drop_reasons": drop_reasons,
    }
    return passed, report, summary


def main() -> int:
    ap = argparse.ArgumentParser(description="采集标准粗筛 + 审计报告")
    ap.add_argument("--in", dest="inp", required=True, help="adapter 产出的 items JSON")
    ap.add_argument("--platform", required=True, help="平台友好名，如 xiaohongshu / douyin")
    ap.add_argument("-o", "--out", default=None, help="通过项输出 JSON（默认 {in}.passed.json）")
    args = ap.parse_args()

    with open(args.inp, "r", encoding="utf-8") as f:
        items = json.load(f)
    if not isinstance(items, list):
        print("输入不是 JSON 数组", file=sys.stderr)
        return 1

    th = thresholds_for(args.platform)
    passed, report, summary = run(items, args.platform)

    print("=" * 72)
    print(f"采集标准 · {args.platform}")
    print(f"  热度门槛：收藏 ≥ {th['collects']} 或 点赞 ≥ {th['likes']}")
    print(f"  完整性：{'需有图/视频 且 ' if REQUIRE_MEDIA else ''}正文 ≥ {MIN_TEXT_LEN} 字")
    print(f"  可体验：{'需有 http/https 外链' if REQUIRE_SOURCE_URL else '（不要求外链）'}")
    print("=" * 72)
    for line in report:
        print(line)
    print("-" * 72)
    print(f"入 {summary['in']} 条 → 通过 {summary['passed']} → 砍 {summary['dropped']}")
    if summary["drop_reasons"]:
        print("砍的原因分布：")
        for k, v in sorted(summary["drop_reasons"].items(), key=lambda x: -x[1]):
            print(f"  · {k}: {v}")

    out = args.out or (args.inp.rsplit(".", 1)[0] + ".passed.json")
    with open(out, "w", encoding="utf-8") as f:
        json.dump(passed, f, ensure_ascii=False, indent=2)
    print("-" * 72)
    print(f"通过项（按收藏降序）已写出 → {out}")
    print(f"下一步：python -m app.pipeline collect {out} --platform {args.platform}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
