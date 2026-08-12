from pathlib import Path
from unittest.mock import patch
import importlib.util
import sys
import unittest


SCRAPE = Path(__file__).resolve().parents[1] / "scrape"
sys.path.insert(0, str(SCRAPE))
SPEC = importlib.util.spec_from_file_location("jike_collector", SCRAPE / "jike_collector.py")
jike = importlib.util.module_from_spec(SPEC)
assert SPEC.loader
SPEC.loader.exec_module(jike)

MEDIA_SPEC = importlib.util.spec_from_file_location(
    "mediacrawler_adapter", SCRAPE / "mediacrawler_adapter.py"
)
media_adapter = importlib.util.module_from_spec(MEDIA_SPEC)
assert MEDIA_SPEC.loader
MEDIA_SPEC.loader.exec_module(media_adapter)


class JikeProjectContractTests(unittest.TestCase):
    def post(self):
        return {
            "id": "p1",
            "type": "ORIGINAL_POST",
            "content": "我用 AI 做了个免费的教授视频生成器 https://work.example/app",
            "urlsInText": [{"url": "https://work.example/app"}],
            "pictures": [{"picUrl": "https://cdn.example/demo.jpg"}],
            "user": {"screenName": "maker"},
        }

    def test_source_and_experience_are_separate(self):
        item = jike._to_project_item(self.post())
        self.assertEqual(item["source_url"], "https://web.okjike.com/originalPost/p1")
        self.assertEqual(item["try_url"], "https://work.example/app")
        self.assertEqual(item["content_kind"], "project")

    def test_social_link_is_not_experience(self):
        post = self.post()
        post["urlsInText"] = [{"url": "https://www.bilibili.com/video/BV1"}]
        post["content"] = "我做了个小游戏 https://www.bilibili.com/video/BV1"
        self.assertIsNone(jike._to_project_item(post))

    def test_no_proof_means_skip(self):
        post = self.post()
        post["pictures"] = []
        with patch.object(jike, "gather_media", return_value=[]):
            self.assertIsNone(jike._to_project_item(post))

    def test_tutorial_is_material_not_work(self):
        post = self.post()
        post["content"] = "保姆级教程：如何使用 Cursor 做了个网站 https://work.example/app"
        self.assertIsNone(jike._to_project_item(post))


class MediaCrawlerConstitutionTests(unittest.TestCase):
    def test_outcome_passes_with_proof_and_heat(self):
        item = {
            "source_url": "https://www.douyin.com/video/1",
            "source_platform": "douyin",
            "title": "我用 Cursor 做了个音乐可视化网站",
            "text": "我用 Cursor 做了个音乐可视化网站，现在已经上线了。",
            "media": [{"url": "https://cdn.example/proof.jpg", "media_type": "image"}],
            "engagement": {"likes": 30000, "collects": 3000},
        }
        passed, reasons = media_adapter._constitution_result(item)
        self.assertTrue(passed, reasons)

    def test_tutorial_is_rejected_even_when_hot(self):
        item = {
            "source_url": "https://www.douyin.com/video/2",
            "source_platform": "douyin",
            "title": "保姆级教程：如何用 Cursor 做网站",
            "text": "保姆级教程，教你怎么用 Cursor 做一个网站。",
            "media": [{"url": "https://cdn.example/proof.jpg", "media_type": "image"}],
            "engagement": {"likes": 30000, "collects": 3000},
        }
        passed, reasons = media_adapter._constitution_result(item)
        self.assertFalse(passed)
        self.assertIn("tutorial_or_material", reasons)

    def test_topic_announcement_is_not_a_work(self):
        item = {
            "source_url": "https://www.douyin.com/video/3",
            "source_platform": "douyin",
            "title": "VibeCoding大赏启动，优秀作品获得流量扶持",
            "text": "活动时间到八月底，参与方式是带话题投稿。",
            "media": [{"url": "https://cdn.example/poster.jpg", "media_type": "image"}],
            "engagement": {"likes": 30000, "collects": 3000},
        }
        passed, reasons = media_adapter._constitution_result(item)
        self.assertFalse(passed)
        self.assertIn("tutorial_or_material", reasons)

    def test_discovery_accepts_save_heavy_work_below_full_douyin_gate(self):
        item = {
            "source_url": "https://www.douyin.com/video/4",
            "source_platform": "douyin",
            "title": "VibeCoding大赏｜我用AI把背单词做成了游戏",
            "text": "展示实际游戏画面和操作效果。",
            "media": [{"url": "https://cdn.example/game.mp4", "media_type": "video"}],
            "engagement": {"likes": 4751, "collects": 3223},
        }
        strict, _ = media_adapter._constitution_result(item)
        discovery, reasons = media_adapter._discovery_result(item)
        self.assertFalse(strict)
        self.assertTrue(discovery, reasons)

    def test_discovery_still_rejects_tutorial(self):
        item = {
            "source_url": "https://www.douyin.com/video/5",
            "source_platform": "douyin",
            "title": "VibeCoding保姆级教程",
            "text": "十秒教你复刻热门网站。",
            "media": [{"url": "https://cdn.example/tutorial.mp4", "media_type": "video"}],
            "engagement": {"likes": 50000, "collects": 5000},
        }
        passed, reasons = media_adapter._discovery_result(item)
        self.assertFalse(passed)
        self.assertIn("tutorial_or_material", reasons)

    def test_review_pool_expands_heat_only(self):
        item = {
            "source_url": "https://www.douyin.com/video/6",
            "source_platform": "douyin",
            "title": "我做了个能玩的音乐可视化网站",
            "text": "展示完整成果画面和实际操作效果。",
            "media": [{"url": "https://cdn.example/work.mp4", "media_type": "video"}],
            "engagement": {"likes": 120, "collects": 35},
        }
        discovery, _ = media_adapter._discovery_result(item)
        review_pool, reasons = media_adapter._review_pool_result(item)
        self.assertFalse(discovery)
        self.assertTrue(review_pool, reasons)

        item["title"] = "保姆级教程：教你做音乐可视化"
        review_pool, reasons = media_adapter._review_pool_result(item)
        self.assertFalse(review_pool)
        self.assertIn("tutorial_or_material", reasons)

    def test_engagement_priority_weights_collects_more_than_likes(self):
        save_heavy = {"source_platform": "douyin", "engagement": {"likes": 5000, "collects": 4000}}
        like_heavy = {"source_platform": "douyin", "engagement": {"likes": 10000, "collects": 1000}}
        self.assertGreater(
            media_adapter._engagement_priority(save_heavy),
            media_adapter._engagement_priority(like_heavy),
        )

    def test_douyin_collect_weight_is_not_applied_to_xiaohongshu(self):
        save_heavy = {"source_platform": "xiaohongshu", "engagement": {"likes": 5000, "collects": 4000}}
        like_heavy = {"source_platform": "xiaohongshu", "engagement": {"likes": 10000, "collects": 1000}}
        self.assertLess(
            media_adapter._engagement_priority(save_heavy),
            media_adapter._engagement_priority(like_heavy),
        )


if __name__ == "__main__":
    unittest.main()
