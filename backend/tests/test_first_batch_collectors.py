from pathlib import Path
import importlib.util
import sys
import unittest
from unittest.mock import patch


SCRAPE = Path(__file__).resolve().parents[1] / "scrape"
sys.path.insert(0, str(SCRAPE))
SPEC = importlib.util.spec_from_file_location("first_batch_collectors", SCRAPE / "first_batch_collectors.py")
collectors = importlib.util.module_from_spec(SPEC)
assert SPEC.loader
SPEC.loader.exec_module(collectors)

PH_SPEC = importlib.util.spec_from_file_location("ph_graphql_collector", SCRAPE / "ph_graphql_collector.py")
ph = importlib.util.module_from_spec(PH_SPEC)
assert PH_SPEC.loader
PH_SPEC.loader.exec_module(ph)


class FirstBatchContractTests(unittest.TestCase):
    def test_item_requires_real_proof(self):
        with patch.object(collectors, "gather_media", return_value=[]):
            self.assertIsNone(collectors.item(
                source="https://source.example/post/1", target="https://work.example/app",
                title="A work", text="A concrete result", platform="example",
            ))

    def test_item_keeps_source_and_experience_separate(self):
        media = [{"url": "https://cdn.example/demo.png", "media_type": "image"}]
        with patch.object(collectors, "gather_media", return_value=media):
            row = collectors.item(
                source="https://source.example/post/1", target="https://work.example/app",
                title="A work", text="A concrete result", platform="example",
            )
        self.assertEqual(row["source_url"], "https://source.example/post/1")
        self.assertEqual(row["try_url"], "https://work.example/app")
        self.assertEqual(row["media"], media)

    def test_sspai_blocks_source_and_video_hosts(self):
        blocked = collectors._SSPAI_BLOCKED_HOST
        self.assertRegex("sspai.com", blocked)
        self.assertRegex("www.bilibili.com", blocked)
        self.assertNotRegex("github.com", blocked)

    def test_product_hunt_company_ads_are_detected(self):
        ads = [
            "Stitch 2.0 by Google Vibe design production-ready UI in seconds",
            "Find and reach target customers with automated multi-channel outreach",
            "High-converting social ads reduce paid acquisition costs by 60%",
        ]
        for text in ads:
            with self.subTest(text=text):
                self.assertRegex(text, ph.COMPANY_AD_RE)
        self.assertNotRegex("I built a tiny rain particle website on weekends", ph.COMPANY_AD_RE)


if __name__ == "__main__":
    unittest.main()
