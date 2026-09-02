import os
import tempfile
import unittest
from types import SimpleNamespace
from unittest.mock import patch

import cv2
import numpy as np

from app.services.video_frames import extract_candidate_frames


class VideoFrameExtractionTest(unittest.TestCase):
    def test_extracts_three_distinct_frames_with_public_urls(self):
        fd, video_path = tempfile.mkstemp(suffix=".avi")
        os.close(fd)
        writer = cv2.VideoWriter(video_path, cv2.VideoWriter_fourcc(*"MJPG"), 15, (640, 360))
        rng = np.random.default_rng(7)
        for index in range(90):
            frame = (
                rng.integers(0, 256, (360, 640, 3), dtype=np.uint8)
                if index in (17, 44, 71)
                else np.full((360, 640, 3), (index * 5) % 255, dtype=np.uint8)
            )
            cv2.putText(frame, f"frame {index}", (40, 180), cv2.FONT_HERSHEY_SIMPLEX,
                        2, (255, 255, 255), 4)
            writer.write(frame)
        writer.release()

        candidate = SimpleNamespace(
            id="test",
            source_platform="douyin",
            media_json={"items": [{"url": "https://video.test/a.mp4", "media_type": "video"}]},
        )

        def fake_save(path, name):
            os.remove(path)
            return "/uploads/" + name

        with patch("app.services.video_frames._download_video", return_value=video_path), patch(
            "app.services.video_frames.save_media_file", side_effect=fake_save
        ):
            frames = extract_candidate_frames(candidate)

        self.assertEqual([item["frame_ratio"] for item in frames], [0.2, 0.5, 0.8])
        self.assertTrue(all(item["url"].startswith("/uploads/frame_") for item in frames))
        self.assertTrue(all(item["generated_from"] == "video_frame" for item in frames))


if __name__ == "__main__":
    unittest.main()
