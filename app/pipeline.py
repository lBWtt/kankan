# ============================================================
# 这个文件是干什么的：AI 抓取管线的"操作台"——运营在命令行跑两步：
#   collect 把抓取的 JSON 条目入池，process 调 Claude 把原料整理成待审核候选。
# 它对应产品里的什么功能：PRD §10 内容抓取流程的日常运转入口（每天更新候选池）。
# 如果它出错了，用户会看到什么现象：运营没法往候选池进货/整理，App 新内容停更。
#
# 用法（在 backend/ 下，激活虚拟环境）：
#   python -m app.pipeline collect 抓取条目.json --platform xiaohongshu
#   python -m app.pipeline process --limit 20      # 需要环境变量 ANTHROPIC_API_KEY
#
# 抓取条目.json 是一个数组，每条至少含 source_url + title，形状见 services/ingestion.py 文件头。
# 各平台的抓取脚本（注意平台 ToS 与图片版权）只要产出这个形状，就能接进管线。
# ============================================================
import argparse
import json
import sys

from app.core.db import SessionLocal
from app.services.ai_processor import process_collected
from app.services.ingestion import ingest_raw_items


def cmd_collect(args) -> int:
    with open(args.file, "r", encoding="utf-8") as f:
        items = json.load(f)
    if not isinstance(items, list):
        print("文件内容必须是 JSON 数组（每个元素一条抓取内容）", file=sys.stderr)
        return 1
    with SessionLocal() as db:
        stats = ingest_raw_items(db, items, default_platform=args.platform)
    print(f"入池 {stats['ingested']} 条；重复跳过 {stats['duplicate']} 条；"
          f"缺 source_url/title 无效 {stats['invalid']} 条")
    return 0


def cmd_process(args) -> int:
    with SessionLocal() as db:
        stats = process_collected(db, limit=args.limit)
    print(f"整理完成 {stats['processed']} 条（其中 {stats['to_review']} 条已进待审核队列）；"
          f"失败 {stats['failed']} 条（详见日志，下次运行会重试）")
    return 0 if stats["failed"] == 0 else 1


def main() -> int:
    parser = argparse.ArgumentParser(prog="python -m app.pipeline", description="AI 抓取管线操作台")
    sub = parser.add_subparsers(dest="command", required=True)

    p_collect = sub.add_parser("collect", help="把抓取的 JSON 条目入候选池（ai_collected）")
    p_collect.add_argument("file", help="JSON 文件路径（数组，每条至少含 source_url + title）")
    p_collect.add_argument("--platform", default=None, help="条目没写来源平台时的默认值")
    p_collect.set_defaults(func=cmd_collect)

    p_process = sub.add_parser("process", help="调 Claude 整理 ai_collected 的候选 → 待审核")
    p_process.add_argument("--limit", type=int, default=20, help="本次最多整理几条（默认 20）")
    p_process.set_defaults(func=cmd_process)

    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
