from types import SimpleNamespace
import unittest
from datetime import datetime, timezone
from uuid import uuid4

from app.core.errors import AppError
from app.services.ai_processor import (
    AnalysisScores,
    _durable_social_proof,
    _resolved_experience_url,
    calibrate_evidence_scores,
    compute_curation_score,
)
from app.services.candidates import _inferred_restore_status, check_publish_gate
from app.services.slate import compose_slate


def _candidate(**overrides):
    data = dict(
        is_work=True,
        title="把招聘要求贴进去简历会逐条帮你改",
        tagline="五秒看懂效果并能立即复用",
        summary="这是一段足够长的项目简介，用来验证内容宪法发布闸的完整字段。",
        category="productivity",
        domains=["design"],
        work_form="prompt",
        creator_type="indie",
        access_friction="instant",
        hook_clarity=80,
        visual_impact=80,
        surprise=70,
        tryability=90,
        shareability=75,
        attraction_score=80,
        value_score=85,
        selected_proof_media={"url": "https://cdn.example.com/result.png", "media_type": "image"},
        experience_type="prompt_content",
        experience_url=None,
        experience_content="请把下面的招聘要求与简历逐项对照并给出修改建议。",
    )
    data.update(overrides)
    return SimpleNamespace(**data)


def _project(index: int, form: str, **overrides):
    data = dict(
        id=uuid4(),
        status="published",
        deleted_at=None,
        attraction_score=95 - index if index < 8 else 81,
        hook_clarity=90,
        visual_impact=90 if index < 3 else 75,
        selected_proof_media={"url": f"https://cdn.example.com/{index}.png"},
        work_form=form,
        creator_type="company" if index == 7 else "indie",
        access_friction="instant",
        experience_type="web",
        source_platform=f"platform-{index // 2}",
        value_score=80 if index < 6 else 60,
        is_direct_tryable=index < 6,
        is_strong_visual=index < 3,
    )
    data.update(overrides)
    return SimpleNamespace(**data)


class ContentConstitutionV11Tests(unittest.TestCase):
    def test_attraction_score_is_computed_by_backend_weights(self):
        scores = AnalysisScores(
            hook_clarity=80,
            visual_impact=90,
            surprise=70,
            tryability=60,
            shareability=50,
        )
        self.assertEqual(compute_curation_score(scores), 73)

    def test_unverified_visual_and_missing_experience_are_capped(self):
        candidate = SimpleNamespace(
            source_platform="douyin",
            raw_json={"published_at": "2026-08-10T00:00:00Z", "engagement": {"likes": 10}},
            human_override_json=None,
        )
        scores = AnalysisScores(
            hook_clarity=85,
            visual_impact=90,
            surprise=85,
            tryability=70,
            shareability=80,
        )
        calibrated, attraction, rules = calibrate_evidence_scores(
            candidate, scores, False, now=datetime(2026, 8, 11, tzinfo=timezone.utc)
        )
        self.assertEqual(calibrated.visual_impact, 70)
        self.assertEqual(calibrated.tryability, 50)
        self.assertEqual(attraction, 75)
        self.assertEqual(
            rules,
            ["unverified_visual_cap_70", "missing_experience_tryability_cap_50"],
        )

    def test_old_low_like_douyin_cannot_reach_82_without_confirmation(self):
        candidate = SimpleNamespace(
            source_platform="douyin",
            raw_json={"published_at": "2026-07-01T00:00:00Z", "engagement": {"likes": 29}},
            human_override_json=None,
        )
        scores = AnalysisScores(
            hook_clarity=100,
            visual_impact=70,
            surprise=100,
            tryability=100,
            shareability=100,
        )
        _, attraction, rules = calibrate_evidence_scores(
            candidate, scores, True, now=datetime(2026, 8, 11, tzinfo=timezone.utc)
        )
        self.assertEqual(attraction, 81)
        self.assertIn("douyin_old_low_engagement_cap_81", rules)

    def test_content_experience_counts_as_available_without_url(self):
        candidate = SimpleNamespace(
            source_platform="jike",
            raw_json={},
            human_override_json=None,
        )
        scores = AnalysisScores(
            hook_clarity=80,
            visual_impact=70,
            surprise=70,
            tryability=85,
            shareability=70,
        )
        calibrated, _, rules = calibrate_evidence_scores(candidate, scores, True)
        self.assertEqual(calibrated.tryability, 85)
        self.assertNotIn("missing_experience_tryability_cap_50", rules)

    def test_verified_visual_and_human_confirmation_bypass_caps(self):
        candidate = SimpleNamespace(
            source_platform="douyin",
            raw_json={
                "published_at": "2026-07-01T00:00:00Z",
                "engagement": {"likes": 29},
                "visual_verification_status": "human_checked",
                "human_score_confirmed": True,
            },
            human_override_json=None,
        )
        scores = AnalysisScores(
            hook_clarity=100,
            visual_impact=90,
            surprise=100,
            tryability=100,
            shareability=100,
        )
        calibrated, attraction, rules = calibrate_evidence_scores(
            candidate, scores, True, now=datetime(2026, 8, 11, tzinfo=timezone.utc)
        )
        self.assertEqual(calibrated.visual_impact, 90)
        self.assertEqual(attraction, 98)
        self.assertEqual(rules, [])

    def test_content_experience_can_publish_without_url(self):
        check_publish_gate(_candidate())

    def test_social_discovery_video_cannot_become_experience_url(self):
        candidate = SimpleNamespace(
            raw_json={"requires_manual_experience_url": True},
            source_platform="douyin",
            source_url="https://www.douyin.com/video/123",
        )
        video_cdn = "https://www.douyin.com/aweme/v1/play/?video_id=abc"
        self.assertIsNone(_resolved_experience_url(candidate, video_cdn))
        self.assertIsNone(
            _resolved_experience_url(candidate, "https://v26-web.douyinvod.com/temporary/video")
        )

    def test_social_collector_verified_external_url_wins(self):
        candidate = SimpleNamespace(
            raw_json={
                "requires_manual_experience_url": True,
                "known_try_url": "https://example.com/the-work",
            },
            source_platform="douyin",
            source_url="https://www.douyin.com/video/123",
        )
        self.assertEqual(
            _resolved_experience_url(candidate, "https://www.douyin.com/aweme/v1/play/?video_id=abc"),
            "https://example.com/the-work",
        )

    def test_social_ephemeral_video_proof_falls_back_to_cover(self):
        cover = {"url": "https://p3.douyinpic.com/cover.jpeg?x-expires=2101773600", "media_type": "image"}
        video = {"url": "https://v26-web.douyinvod.com/temporary/video", "media_type": "video"}
        candidate = SimpleNamespace(
            source_platform="douyin",
            media_json={"items": [cover, video]},
        )
        self.assertEqual(_durable_social_proof(candidate, video), cover)

    def test_unknown_experience_type_is_rejected(self):
        with self.assertRaises(AppError):
            check_publish_gate(_candidate(experience_type="unknown"))

    def test_publish_gate_rejects_quality_failures(self):
        failures = [
            {"attraction_score": 69},
            {"selected_proof_media": None},
            {"experience_type": "web", "experience_url": "not-a-url", "experience_content": None},
            {"experience_type": "web", "experience_url": "https://github.com/example/project", "experience_content": None},
        ]
        for changes in failures:
            with self.subTest(changes=changes), self.assertRaises(AppError):
                check_publish_gate(_candidate(**changes))

    def test_legacy_discard_restore_infers_original_workflow_layer(self):
        raw = SimpleNamespace(
            human_override_json=None, ai_analysis_json=None, ai_curation_score=None,
            content_kind="project",
        )
        self.assertEqual(_inferred_restore_status(raw), "ai_collected")

        ready = _candidate()
        ready.content_kind = "project"
        ready.human_override_json = None
        ready.ai_analysis_json = {"is_work": True}
        ready.ai_curation_score = ready.attraction_score
        self.assertEqual(_inferred_restore_status(ready), "pending_review")

        missing_experience = _candidate(
            experience_type="web", experience_url=None, experience_content=None,
        )
        missing_experience.content_kind = "project"
        missing_experience.human_override_json = None
        missing_experience.ai_analysis_json = {"is_work": True}
        missing_experience.ai_curation_score = missing_experience.attraction_score
        self.assertEqual(_inferred_restore_status(missing_experience), "ai_processed")

        missing_experience.human_override_json = {"experience_url": None}
        self.assertEqual(_inferred_restore_status(missing_experience), "edited")

    def test_slate_satisfies_all_v11_constraints_when_inventory_allows(self):
        forms = ["app", "website", "game", "tool", "prompt", "ai_art", "model", "workflow", "app", "website", "game", "tool"]
        result = compose_slate([_project(i, form) for i, form in enumerate(forms)], seed="test")
        items = result.projects
        self.assertEqual(len(items), 10)
        self.assertEqual(result.shortages, [])
        self.assertGreaterEqual(items[0].attraction_score, 82)
        self.assertGreaterEqual(items[0].hook_clarity, 80)
        self.assertGreaterEqual(items[0].visual_impact, 80)
        self.assertGreaterEqual(sum(p.attraction_score >= 82 for p in items), 6)
        self.assertGreaterEqual(sum(bool(p.is_direct_tryable) for p in items), 4)
        self.assertGreaterEqual(sum((p.value_score or 0) >= 70 for p in items), 3)
        self.assertGreaterEqual(sum(bool(p.is_strong_visual) for p in items), 2)
        self.assertLessEqual(sum(p.creator_type == "company" for p in items), 1)
        for a, b in zip(items, items[1:]):
            a_restricted = a.source_platform == "github" or a.work_form in {"model", "workflow"}
            b_restricted = b.source_platform == "github" or b.work_form in {"model", "workflow"}
            self.assertFalse(a_restricted and b_restricted)

    def test_slate_returns_shortage_instead_of_relaxing_quality_gate(self):
        weak = _project(0, "app", attraction_score=69)
        result = compose_slate([weak], seed="test")
        self.assertEqual(result.projects, [])
        self.assertTrue(result.shortages)


if __name__ == "__main__":
    unittest.main()
