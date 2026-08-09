# ============================================================
# 这个文件是干什么的：内容流水线的**一键驱动**——把"采集→粗筛→入池→富化(→审核/发布)"
#   焊成一条命令，规则写死在代码里，防止"下次忘"。SSOT 见根 CONTENT_PIPELINE.md。
#
# 决策（已和用户拍板，写死）：
#   - 所有来源（包括 GitHub）→ 富化后停在**待审核队列**，一律人工最终过审。
#   - 口吻**对照即刻真帖**（jike 跑完自动刷新 scrape/jike_voice_samples.json 口吻样本库）。
#   - 节奏：手动 on-demand（本脚本就是手动入口）。
#
# 用法（在 backend/ 下；DeepSeek/GitHub key 只经环境变量传，别写进文件）：
#   $env:DEEPSEEK_API_KEY="sk-xxx"; $env:GITHUB_TOKEN="ghp_xxx"
#   python scrape/pipeline_run.py github --limit 40
#   python scrape/pipeline_run.py ph    --limit 30                  # Product Hunt：直连、无需登录/代理
#   python scrape/pipeline_run.py jike  --scrolls 10 --headful      # 首次扫码；之后免扫可去掉 --headful
#   python scrape/pipeline_run.py xhs   --mc-dir F:/MediaCrawler     # 需先用 MediaCrawler 抓好
#   python scrape/pipeline_run.py dy    --mc-dir F:/MediaCrawler
# ============================================================
import argparse
import json
import os
import re
import subprocess
import sys
import time

BACKEND = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # .../backend
PY = sys.executable  # 后端 python（3.9）
# 即刻用 Playwright，得用 mediacrawler 环境（3.11 + chromium）；可用环境变量覆盖路径。
MEDIACRAWLER_PY = os.environ.get("MEDIACRAWLER_PY", "D:/conda/envs/mediacrawler/python.exe")


def run(cmd, extra_env=None):
    """在 backend/ 下跑子命令，出错即抛。DeepSeek/GitHub key 从当前环境继承。"""
    env = dict(os.environ)
    if extra_env:
        env.update(extra_env)
    print(f"\n$ {' '.join(cmd)}")
    subprocess.check_call(cmd, cwd=BACKEND, env=env)


def _deepseek_env():
    if not os.environ.get("DEEPSEEK_API_KEY"):
        print("!! 没设 DEEPSEEK_API_KEY，富化会失败。先 set DEEPSEEK_API_KEY=sk-xxx", file=sys.stderr)
    return {"AI_PROVIDER": "deepseek", "PYTHONIOENCODING": "utf-8"}


def _process():
    run([PY, "-m", "app.pipeline", "process", "--limit", "60"], _deepseek_env())


# ---------------- 口吻样本库（对照即刻真人，用户硬要求）----------------
def refresh_voice_bank(items_jike="items_jike.json", out="scrape/jike_voice_samples.json"):
    """即刻抓完自动刷新口吻样本库：取真帖正文（≥25 字）当风格参照。"""
    path = os.path.join(BACKEND, items_jike)
    if not os.path.exists(path):
        return
    try:
        data = json.load(open(path, encoding="utf-8"))
    except Exception:
        return
    # 短帖是最好的口吻样本（punchy、有网感），别过滤掉；只砍几乎空的。
    samples = [{"author": it.get("original_author_name"), "text": (it.get("text") or "").strip()[:400]}
               for it in data if len((it.get("text") or "").strip()) >= 8]
    if samples:
        json.dump(samples, open(os.path.join(BACKEND, out), "w", encoding="utf-8"),
                  ensure_ascii=False, indent=2)
        print(f"  已用 {len(samples)} 条即刻真帖刷新口吻样本库 → {out}")


# ---------------- 各源入口 ----------------
def cmd_github(args):
    run([PY, "scrape/github_collector.py", "-o", "items_github.json", "--limit", str(args.limit)])
    run([PY, "scrape/prefilter.py", "--in", "items_github.json", "--platform", "github",
         "-o", "items_github_passed.json"])
    run([PY, "-m", "app.pipeline", "collect", "items_github_passed.json", "--platform", "github"])
    _process()
    print("\nGitHub 内容已进待审核队列；内容宪法 v1.1 禁止任何来源自动发布。")


def cmd_jike(args):
    jargs = [MEDIACRAWLER_PY, "scrape/jike_collector.py", "-o", "items_jike.json",
             "--dump-raw", "jike_raw.json", "--scrolls", str(args.scrolls)]
    if args.headful:
        jargs.append("--headful")
    run(jargs)
    refresh_voice_bank()  # 用真帖刷新口吻样本库
    run([PY, "-m", "app.pipeline", "collect", "items_jike.json", "--platform", "jike", "--kind", "post"])
    _process()
    print("\n即刻动态已进**待审核队列**（人工审核后发布：管理员端 approve → 建 Post）。")


def cmd_x(args):
    xargs = [MEDIACRAWLER_PY, "scrape/x_collector.py", "--query", args.query,
             "-o", "items_x.json", "--dump-raw", "x_raw.json", "--scrolls", str(args.scrolls)]
    if args.headful:
        xargs.append("--headful")
    if args.latest:
        xargs.append("--latest")
    run(xargs)
    # X 跳过 prefilter（多是文字+链接，项目粗筛要图会误砍）；成果/水由 DeepSeek is_maker_showcase 判。
    run([PY, "-m", "app.pipeline", "collect", "items_x.json", "--platform", "x"])
    _process()
    print("\nX 内容已进**待审核队列**（DeepSeek 已翻译成中文+判成果/提链接；人工审确认成果+补链接后发布）。")


def cmd_producthunt(args):
    # PH 直连可达、无需登录/代理；collector 内做「国区可达 + 商店锁区」过滤。
    run([PY, "scrape/ph_collector.py", "-o", "items_ph.json", "--limit", str(args.limit)])
    # PH 无热度可粗筛（feed 不给票数），跳过 prefilter；成果/水交 DeepSeek + 人工审。
    run([PY, "-m", "app.pipeline", "collect", "items_ph.json", "--platform", "producthunt"])
    _process()
    print("\nProduct Hunt 内容已进**待审核队列**（DeepSeek 已翻译成中文+判成果+带体验链接；人工审后发布）。")


def cmd_githubdaily(args):
    # GitHubDaily 年度复盘直连可达、无需登录/代理；只取「工具/应用/插件」板块，每条抓 og 封面。
    # 已是中文策展、每条自带项目链接（多为 GitHub 仓库＝天然 try_url）；成果/水交 DeepSeek + 人工审。
    run([PY, "scrape/github_daily_collector.py", "-o", "items_ghd.json", "--limit", str(args.limit)])
    run([PY, "-m", "app.pipeline", "collect", "items_ghd.json", "--platform", "githubdaily"])
    _process()
    print("\nGitHubDaily 内容已进**待审核队列**（DeepSeek 换角度写中文+判成果+带体验链接；人工审后发布）。")


def cmd_phrank(args):
    # PH 榜单（GraphQL，top-by-votes ≈ 月榜/周榜）：真实产品 + PH 画廊多图 + makers。
    # 需 PH_KEY / PH_SECRET 内联（run() 继承 os.environ）；makers 自动登记进 sources.yaml。
    run([PY, "scrape/ph_graphql_collector.py", "-o", "items_phg.json",
         "--limit", str(args.limit), "--days", str(args.days)])
    run([PY, "-m", "app.pipeline", "collect", "items_phg.json", "--platform", "producthunt"])
    _process()
    print("\nPH 榜单内容已进**待审核队列**（真实产品 + 多图 + 创作者；人工审后发布）。")


def cmd_showhn(args):
    # Hacker News Show HN：开发者秀自己做的成品，Algolia API 直连、免登录；带真实作者。
    # 取最近的高赞（--min-points），过滤无 url/自引用；封面走 best_cover（含网页截图兜底）。
    run([PY, "scrape/showhn_collector.py", "-o", "items_shn.json",
         "--limit", str(args.limit), "--min-points", str(args.min_points)])
    run([PY, "-m", "app.pipeline", "collect", "items_shn.json", "--platform", "hackernews"])
    _process()
    print("\nShow HN 内容已进**待审核队列**（DeepSeek 换角度写中文+判成果+带体验链接；人工审后发布）。")


def cmd_appinn(args):
    # 小众软件 appinn：中文老牌实用软件/网站策展，WordPress RSS；按分类过滤掉新闻/补丁/榜单。
    # feed 只给最近 ~10 篇，过滤后每次约 5~7 条软件；封面用正文真实截图。
    run([PY, "scrape/appinn_collector.py", "-o", "items_appinn.json", "--limit", str(args.limit)])
    run([PY, "-m", "app.pipeline", "collect", "items_appinn.json", "--platform", "appinn"])
    _process()
    print("\n小众软件 内容已进**待审核队列**（DeepSeek 换角度写中文+判成果+带体验链接；人工审后发布）。")


def cmd_hellogithub(args):
    # HelloGitHub 月刊直连可达、无需登录/代理；自动取最新期，每条自带项目截图（省 og 抓取）。
    # 中文策展·偏基建（配角），链接解出 target＝真实 GitHub 仓库＝天然 try_url；成果/水交 DeepSeek + 人工审。
    run([PY, "scrape/hellogithub_collector.py", "-o", "items_hg.json", "--limit", str(args.limit)])
    run([PY, "-m", "app.pipeline", "collect", "items_hg.json", "--platform", "hellogithub"])
    _process()
    print("\nHelloGitHub 内容已进**待审核队列**（DeepSeek 换角度写中文+判成果+带体验链接；人工审后发布）。")


# 来源友好名 → 库里 source_platform 真值（ph/xhs/dy 是简写）。
_PLATFORM_ALIAS = {"ph": "producthunt", "xhs": "xiaohongshu", "dy": "douyin"}


def cmd_publish(args):
    """把待审核候选**批量过审发布**——就是「你在审核后台点 approve」的脚本版：
    建项目/动态 + 随机派马甲作者 + 封面转存本地/OSS。默认只发 pending_review（已过 AI 闸）。
    这样「采集→整理→发布」整条都是命令，换任何 AI 跑同一条命令结果一致（发布不再靠手动内联）。"""
    from sqlalchemy import select
    from app.core.db import SessionLocal
    from app.models import CandidateContent, User
    from app.services.candidates import approve_candidate, approve_candidate_as_post
    from app.core.errors import AppError

    statuses = ("pending_review", "edited")
    if args.include_processed:
        statuses += ("ai_processed",)
    platform = _PLATFORM_ALIAS.get(args.platform, args.platform)
    with SessionLocal() as db:
        admin = db.query(User).filter(User.is_admin.is_(True)).first() or db.query(User).first()
        q = select(CandidateContent).where(CandidateContent.status.in_(statuses))
        if platform:
            q = q.where(CandidateContent.source_platform == platform)
        # 默认不批量发动态：动态（马甲发的帖）走人工审核，别被这条脚本一把梭发出去。
        # 要连动态一起发，显式加 --include-posts。
        if not args.include_posts:
            q = q.where(CandidateContent.content_kind == "project")
        cands = db.scalars(q).all()
        print(f"待发布：{len(cands)} 条（来源={platform or '全部'}，状态={statuses}，"
              f"{'含动态' if args.include_posts else '仅项目'}）")
        ok = fail = 0
        for c in cands:
            try:
                # 按内容类型分发到对的函数：动态→马甲发帖，项目→建项目。
                # 原来对所有候选都调 approve_candidate（项目函数），会把动态错发成项目/报错。
                if c.content_kind == "post":
                    approve_candidate_as_post(db, c, admin)
                else:
                    approve_candidate(db, c, admin)
                db.commit(); ok += 1
            except (AppError, Exception):
                db.rollback(); fail += 1
        print(f"发布完成：成功 {ok} / 失败·跳过 {fail}")


def cmd_mediacrawler(args, platform, friendly):
    run([PY, "scrape/mediacrawler_adapter.py", "--dir", args.mc_dir, "--platform", platform,
         "-o", f"items_{platform}.json"])
    run([PY, "scrape/prefilter.py", "--in", f"items_{platform}.json", "--platform", friendly,
         "-o", f"items_{platform}_passed.json"])
    run([PY, "-m", "app.pipeline", "collect", f"items_{platform}_passed.json", "--platform", friendly])
    _process()
    print(f"\n{friendly} 内容已进**待审核队列**（人工审核后发布）。")


def main() -> int:
    ap = argparse.ArgumentParser(description="内容流水线一键驱动（规则见 CONTENT_PIPELINE.md）")
    sub = ap.add_subparsers(dest="source", required=True)

    g = sub.add_parser("github", help="项目·GitHub（只入待审核队列，不自动发布）")
    g.add_argument("--limit", type=int, default=40)
    g.set_defaults(func=cmd_github)

    j = sub.add_parser("jike", help="动态·即刻（人工审核）")
    j.add_argument("--scrolls", type=int, default=10)
    j.add_argument("--headful", action="store_true", help="首次扫码登录用")
    j.set_defaults(func=cmd_jike)

    ph = sub.add_parser("ph", help="项目·Product Hunt（人工审核，国区可达过滤，无需登录/代理）")
    ph.add_argument("--limit", type=int, default=30)
    ph.set_defaults(func=cmd_producthunt)

    ghd = sub.add_parser("githubdaily", help="项目·GitHubDaily 复盘（人工审核，中文策展，无需登录/代理）")
    ghd.add_argument("--limit", type=int, default=30)
    ghd.set_defaults(func=cmd_githubdaily)

    hg = sub.add_parser("hellogithub", help="项目·HelloGitHub 月刊（人工审核，中文策展，自带截图，无需登录/代理）")
    hg.add_argument("--limit", type=int, default=30)
    hg.set_defaults(func=cmd_hellogithub)

    shn = sub.add_parser("showhn", help="项目·HN Show HN（人工审核，个人成品+作者，无需登录/代理）")
    shn.add_argument("--limit", type=int, default=30)
    shn.add_argument("--min-points", type=int, default=30)
    shn.set_defaults(func=cmd_showhn)

    ai = sub.add_parser("appinn", help="项目·小众软件 appinn（人工审核，中文实用软件，无需登录/代理）")
    ai.add_argument("--limit", type=int, default=20)
    ai.set_defaults(func=cmd_appinn)

    pr = sub.add_parser("phrank", help="项目·PH 榜单（GraphQL top-by-votes + 多图 + makers，需 PH_KEY/PH_SECRET 内联）")
    pr.add_argument("--limit", type=int, default=30)
    pr.add_argument("--days", type=int, default=30)
    pr.set_defaults(func=cmd_phrank)

    pub = sub.add_parser("publish", help="批量过审发布待审核候选（审核后台 approve 的脚本版）")
    pub.add_argument("--platform", default=None,
                     help="只发某来源：ph/x/github/jike/xhs/dy（不填=全部待审）")
    pub.add_argument("--include-processed", action="store_true",
                     help="连缺料的 ai_processed 也试发（默认只发 pending_review）")
    pub.add_argument("--include-posts", action="store_true",
                     help="连动态一起批量发（默认只发项目；动态默认留人工审）")
    pub.set_defaults(func=cmd_publish)

    xp = sub.add_parser("x", help="项目·推特X（人工审核，首次登录）")
    xp.add_argument("--query", default="vibe coding", help="搜索词")
    xp.add_argument("--scrolls", type=int, default=12)
    xp.add_argument("--headful", action="store_true", help="首次登录用")
    xp.add_argument("--latest", action="store_true", help="按最新而非热门")
    xp.set_defaults(func=cmd_x)

    for plat, friendly in (("xhs", "xiaohongshu"), ("dy", "douyin")):
        m = sub.add_parser(plat, help=f"项目·{friendly}（人工审核，需先用 MediaCrawler 抓好）")
        m.add_argument("--mc-dir", default="F:/MediaCrawler")
        m.set_defaults(func=lambda a, p=plat, f=friendly: cmd_mediacrawler(a, p, f))

    args = ap.parse_args()
    return args.func(args) or 0


if __name__ == "__main__":
    sys.exit(main())
