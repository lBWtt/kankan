# ============================================================
# 这个文件是干什么的：AI 抓取管线的冒烟测试——入池查重、假 LLM 整理（不花 API 钱）、
#   评分加权、宁缺勿错的实现思路、CLI 操作台，最后走真实 API 审核通过到正式发布的全链路。
# 它对应产品里的什么功能：候选池的"进货→整理→审核→上架"流水线。
# 如果它出错了，用户会看到什么现象：App 新内容断供、候选池混进重复/缺料内容、
#   或 AI 整理的字段（分类/评分/实现思路）不可信加重审核负担。
# 用法：先起服务（uvicorn app.main:app），再在 backend/ 下跑：
#   .venv/Scripts/python.exe tests/smoke_v6.py [BASE_URL，默认 http://127.0.0.1:8000]
# ============================================================
import json
import os
import subprocess
import sys
import tempfile
import time
import uuid as uuidlib

import httpx
from sqlalchemy import text as sql

from app.core.db import SessionLocal, engine
from app.core.errors import AppError
from app.models import CandidateContent
from app.services.ai_processor import (
    AnalysisScores, CandidateAnalysis, claude_analyze, compute_curation_score, process_collected,
)
from app.services.ingestion import ingest_raw_items

BASE = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8000"
MARK = f"管线{int(time.time()) % 100000}"

passed, failed = 0, 0
candidate_ids, project_ids, tag_names = [], [], []


def check(name: str, cond: bool, extra=""):
    global passed, failed
    if cond:
        passed += 1
        print(f"  PASS  {name}")
    else:
        failed += 1
        print(f"  FAIL  {name}  {extra}")


def raw_item(suffix: str, **over) -> dict:
    item = {
        "source_url": f"https://example.com/{MARK}/{suffix}",
        "title": f"{MARK}-{suffix} 原文标题",
        "text": "原始正文：作者用 Claude 把周报自动化了，附带完整提示词和截图。",
        "source_platform": "xiaohongshu",
        "original_author_name": f"@作者{suffix}",
        "media": [f"/uploads/{MARK}/{suffix}.png"],
    }
    item.update(over)
    return item


def analysis(title: str, scores: AnalysisScores, **over) -> CandidateAnalysis:
    fields = dict(
        is_work=True, work_rejection_reason=None, work_form="prompt", creator_type="indie",
        access_friction="instant", title_candidates=[title, (title+"更省时间")[:28]],
        hook_sentence="把每周写周报这件事完全交给 AI", category="work_efficiency",
        summary="作者把周报流程交给 AI：自动汇总本周记录、按模板生成草稿，再人工微调，每周省一小时。",
        description="详细介绍：先收集本周的待办与会议记录，让 AI 按固定模板汇总成周报草稿，最后人工补充关键数据。",
        domains=["office", "dev"], tools=["Claude"], tags=[f"{MARK}标签", "周报自动化"],
        target_users=["上班族"], use_cases=["每周写周报"],
        implementation_steps=["整理本周记录喂给 AI", "用固定模板生成草稿", "人工核对关键数据"],
        scores=scores, value_score=85, risk_flags=[], risk_note=None, why_recommend="人人都要写周报，共鸣强",
        experience_type="prompt_content", experience_url=None,
        experience_content="把本周记录按固定模板整理成周报草稿", selected_proof_media_index=0,
    )
    fields.update(over)
    return CandidateAnalysis(**fields)


# 假 LLM：按原文标题分发固定结果——A 高分全字段、B 中分且"没把握不填思路"、E 缺封面照常整理、F 抛错
def fake_analyze(payload: dict) -> CandidateAnalysis:
    title = payload["原文标题"]
    if "-A " in title:
        return analysis(f"{MARK}A让AI替你写完每周周报", AnalysisScores(
            hook_clarity=92, visual_impact=90, surprise=85, tryability=88, shareability=80))
    if "-B " in title:
        return analysis(f"{MARK}B 英文教程：AI 自动整理收件箱",
                        AnalysisScores(hook_clarity=70, visual_impact=70, surprise=70, tryability=70, shareability=70),
                        implementation_steps=None,
                        risk_flags=["low_quality"], risk_note="原文信息量偏低，方法描述含糊")
    if "-E " in title:
        return analysis(f"{MARK}E无图但标题长度符合要求", AnalysisScores(
            hook_clarity=75, visual_impact=75, surprise=75, tryability=75, shareability=75))
    raise ValueError(f"模拟整理失败：{title}")


def main():
    print("== 1. 入池（ingestion：查重 + 原料保全）==")
    with SessionLocal() as db:
        stats = ingest_raw_items(db, [
            raw_item("A", media=[f"/uploads/{MARK}/a1.png", f"/uploads/{MARK}/a2.png"]),
            raw_item("B", title="pipeline-B Automate your inbox with AI",  # 纯英文：验证语言猜测
                     text="Original post: the author wired Claude to triage email automatically.",
                     media=[f"/uploads/{MARK}/b1.png",
                            {"url": f"/uploads/{MARK}/b.mp4", "media_type": "video",
                             "thumbnail_url": f"/uploads/{MARK}/b_thumb.png"}]),
            {"source_url": f"https://example.com/{MARK}/no-title", "text": "没有标题的坏条目"},
            raw_item("A"),  # 同批重复（同 source_url）
            raw_item("E", media=[]),   # 无媒体：整理后应停在 ai_processed
            raw_item("F"),             # 假 LLM 对它抛错：验证单条失败不卡整批
        ])
        check("批量入池统计：4 入池 / 1 重复 / 1 无效",
              stats == {"ingested": 4, "duplicate": 1, "invalid": 1}, str(stats))

        rows = {c.source_url.rsplit("/", 1)[-1]: c for c in db.query(CandidateContent).filter(
            CandidateContent.source_url.like(f"https://example.com/{MARK}/%")).all()}
        candidate_ids.extend(str(c.id) for c in rows.values())
        a, b = rows["A"], rows["B"]
        check("入池状态 = ai_collected / 来源 = ai_crawled",
              a.status == "ai_collected" and a.source_type == "ai_crawled")
        check("raw_json 保全原文标题与正文",
              a.raw_json["title"] == f"{MARK}-A 原文标题" and "周报" in a.raw_json["text"])
        check("封面取第一张图 + media_json 两条", a.cover_media_url.endswith("a1.png")
              and len(a.media_json["items"]) == 2)
        check("媒体字典形状保留 video/缩略图", b.media_json["items"][1]["media_type"] == "video"
              and b.media_json["items"][1]["thumbnail_url"].endswith("b_thumb.png"))
        check("语言猜测：中文→zh-CN，英文→en-US", a.language == "zh-CN" and b.language == "en-US")

        stats = ingest_raw_items(db, [raw_item("A")])
        check("再次入同链接 = 数据库级查重", stats["duplicate"] == 1 and stats["ingested"] == 0)

        # 已是正式项目的来源链接也算重复
        pid = str(uuidlib.uuid4())
        db.execute(sql("""
            INSERT INTO projects (id, title, tagline, summary, category, language, source_type,
                                  is_original, source_url, status, hot_score)
            VALUES (CAST(:id AS uuid), '已上架项目', '占位亮点啊', :s, 'work_efficiency', 'zh-CN',
                    'ai_crawled', false, :u, 'published', 0)
        """), {"id": pid, "s": "占位简介——超过二十个字以满足数据库与契约的最短长度要求。",
               "u": f"https://example.com/{MARK}/already-published"})
        db.commit()
        project_ids.append(pid)
        stats = ingest_raw_items(db, [raw_item("X", source_url=f"https://example.com/{MARK}/already-published")])
        check("与已发布项目同链接 = 重复跳过", stats["duplicate"] == 1 and stats["ingested"] == 0)

    print("== 2. AI 整理（假 LLM 注入，不花 API 钱）==")
    with SessionLocal() as db:
        stats = process_collected(db, limit=20, analyze=fake_analyze)
        check("整理统计：3 成功 / 2 进待审 / 1 失败",
              stats["processed"] >= 3 and stats["to_review"] >= 2 and stats["failed"] >= 1, str(stats))

        rows = {c.source_url.rsplit("/", 1)[-1]: c for c in db.query(CandidateContent).filter(
            CandidateContent.source_url.like(f"https://example.com/{MARK}/%")).all()}
        a, b, e, f_ = rows["A"], rows["B"], rows["E"], rows["F"]
        check("A 字段齐 → pending_review 进审核队列", a.status == "pending_review")
        check("A 加权分 = 88（25/25/20/15/15 权重）", a.ai_curation_score == 88, str(a.ai_curation_score))
        check("A 实现思路带【AI 推测】标注 + 3 步",
              a.ai_implementation_hint.startswith("【AI 推测") and "3. " in a.ai_implementation_hint,
              str(a.ai_implementation_hint))
        check("A scores_json 留审计（权重+合成分）", a.scores_json["attraction_score"] == 88
              and a.scores_json["weights"]["hook_clarity"] == 0.25)
        check("A tags_json 形状 = {items: [...]}", a.tags_json == {"items": [f"{MARK}标签", "周报自动化"]})
        check("A 整理后原文仍在 raw_json（外文处理红线）", a.raw_json["title"] == f"{MARK}-A 原文标题")
        check("B 没把握 → 实现思路置空（宁缺勿错）",
              b.status == "pending_review" and b.ai_implementation_hint is None)
        check("B 中分 = 70 + 风险标记落库", b.ai_curation_score == 70
              and b.risk_flags == ["low_quality"] and bool(b.risk_note))
        check("B 外文已生成中文标题", b.title.startswith(f"{MARK}B"))
        check("E 缺封面 → 停在 ai_processed 不进审核队列", e.status == "ai_processed")
        check("F 整理失败 → 保持 ai_collected 可重跑", f_.status == "ai_collected")

    try:
        claude_analyze({"原文标题": "x"})
        check("未配 API key 调真实整理 = 明确报错", False, "竟然没拦")
    except AppError as err:
        check("未配 API key 调真实整理 = 明确报错", "ANTHROPIC_API_KEY" in err.message)

    print("== 3. CLI 操作台（python -m app.pipeline collect）==")
    tmp = os.path.join(tempfile.gettempdir(), f"smoke_v6_{MARK}.json")
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump([raw_item("CLI", source_platform=None)], fh, ensure_ascii=False)
    proc = subprocess.run(
        [sys.executable, "-X", "utf8", "-m", "app.pipeline", "collect", tmp, "--platform", "jike"],
        capture_output=True, text=True, encoding="utf-8", errors="replace",
        cwd=os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        env={**os.environ, "PYTHONPATH": ".", "PYTHONIOENCODING": "utf-8"},
    )
    os.remove(tmp)
    check("collect 命令退出码 0 且报告入池 1 条", proc.returncode == 0 and "入池 1 条" in proc.stdout,
          proc.stdout + proc.stderr)
    with SessionLocal() as db:
        cli_row = db.query(CandidateContent).filter(
            CandidateContent.source_url == f"https://example.com/{MARK}/CLI").one_or_none()
        check("CLI 入池行存在且 --platform 默认值生效",
              cli_row is not None and cli_row.source_platform == "jike")
        if cli_row:
            candidate_ids.append(str(cli_row.id))

    print("== 4. 全链路：整理产物走真实 API 审核 → 上架 ==")
    c = httpx.Client(base_url=BASE, timeout=15, trust_env=False)  # trust_env=False 绕过本机代理
    check("GET /health = 200", c.get("/health").status_code == 200)
    phone = f"137{int(time.time()) % 100000000:08d}"
    r = c.post("/api/v1/auth/login", json={"identifier_type": "phone", "identifier": phone, "code": "888888"})
    admin_uid, auth = r.json()["user"]["id"], {"Authorization": f"Bearer {r.json()['access_token']}"}
    with engine.begin() as conn:
        conn.execute(sql("UPDATE users SET is_admin = true WHERE id = :id"), {"id": admin_uid})

    r = c.get("/api/v1/admin/candidates", headers=auth,
              params={"status": "pending_review", "q": MARK, "min_score": 80})
    items = r.json().get("items", [])
    check("待审队列按分数筛到 A（88 分）", r.status_code == 200 and len(items) == 1
          and items[0]["ai_curation_score"] == 88, r.text[:200])
    aid = items[0]["id"]
    r = c.get("/api/v1/admin/candidates", headers=auth, params={"status": "pending_review", "q": MARK, "has_risk": "true"})
    check("风险筛选命中 B", r.status_code == 200 and len(r.json()["items"]) == 1)
    bid = r.json()["items"][0]["id"]

    r = c.post(f"/api/v1/admin/candidates/{aid}/approve", headers=auth)
    check("approve A = 201 → 复制成正式项目", r.status_code == 201, r.text[:200])
    pid_a = r.json()["project_id"]
    project_ids.append(pid_a)
    d = c.get(f"/api/v1/projects/{pid_a}").json()
    check("项目已发布且 ai_badge=high_potential（88≥80）",
          d.get("status", "published") != "draft" and d.get("ai_badge") == "high_potential", str(d.get("ai_badge")))
    check("来源链接/原作者随复制保留（外部内容红线）",
          d.get("source_url", "").endswith("/A") and d.get("original_author_name") == "@作者A")
    check("AI 实现思路带到正式项目（线索页原料）",
          str(d.get("ai_implementation_hint", "")).startswith("【AI 推测"))
    check("媒体从 media_json 落表（2 条）", len(d.get("media", [])) == 2)
    check("标签已拆解", f"{MARK}标签" in d.get("tags", []), str(d.get("tags")))

    r = c.post(f"/api/v1/admin/candidates/{bid}/approve", headers=auth)
    check("approve B = 201（风险标记不阻断，人工确认即放行）", r.status_code == 201, r.text[:200])
    pid_b = r.json()["project_id"]
    project_ids.append(pid_b)
    check("B 70 分 → worth_a_look", c.get(f"/api/v1/projects/{pid_b}").json().get("ai_badge") == "worth_a_look")

    with SessionLocal() as db:
        eid = str(db.query(CandidateContent).filter(
            CandidateContent.source_url == f"https://example.com/{MARK}/E").one().id)
    r = c.post(f"/api/v1/admin/candidates/{eid}/approve", headers=auth)
    check("缺封面的 E 直接 approve = 409 PUBLISH_GATE_FAILED（与整理同一把尺子）",
          r.status_code == 409 and r.json()["code"] == "PUBLISH_GATE_FAILED", r.text[:200])

    # ---- 清理本轮测试数据（保持 dev 库干净）----
    with engine.begin() as conn:
        for pid in project_ids:
            conn.execute(sql("DELETE FROM project_tag_relations WHERE project_id = CAST(:p AS uuid)"), {"p": pid})
            conn.execute(sql("DELETE FROM project_media WHERE project_id = CAST(:p AS uuid)"), {"p": pid})
        conn.execute(sql("DELETE FROM project_tags WHERE name IN (:t1, '周报自动化')"), {"t1": f"{MARK}标签"})
        conn.execute(sql("DELETE FROM candidate_contents WHERE source_url LIKE :u"),
                     {"u": f"https://example.com/{MARK}/%"})
        for pid in project_ids:
            conn.execute(sql("DELETE FROM projects WHERE id = CAST(:p AS uuid)"), {"p": pid})
        conn.execute(sql("DELETE FROM admin_actions WHERE admin_user_id = CAST(:u AS uuid)"), {"u": admin_uid})
        conn.execute(sql("DELETE FROM push_preferences WHERE user_id = CAST(:u AS uuid)"), {"u": admin_uid})
        conn.execute(sql("DELETE FROM users WHERE id = CAST(:u AS uuid)"), {"u": admin_uid})

    print(f"\n结果：{passed} 通过 / {failed} 失败")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
