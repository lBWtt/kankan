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


if __name__ == "__main__":
    unittest.main()
