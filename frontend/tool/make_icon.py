# -*- coding: utf-8 -*-
"""从 Stitch 定稿源图生成「看看」Android 图标资源。

输入：assets/icon/app_icon_stitch_source.png（1024×1024，绿底三笔 K）
输出：assets/icon/app_icon.png（legacy 全幅图）
      assets/icon/app_icon_fg.png（Android adaptive icon 透明前景）

源图保留不覆盖，方便以后替换候选或重新生成。自适应背景色见 pubspec.yaml。
"""
from pathlib import Path

from PIL import Image

N = 1024
BACKGROUND = (9, 96, 64)  # 源图中心附近的品牌绿；adaptive icon 使用同色纯底。
SOURCE = Path(__file__).resolve().parent.parent / "assets" / "icon" / "app_icon_stitch_source.png"
OUT_DIR = SOURCE.parent


def require_square(image: Image.Image) -> None:
    if image.size != (N, N):
        raise ValueError(f"icon source must be {N}x{N}, got {image.size}")


source = Image.open(SOURCE).convert("RGBA")
require_square(source)

# Legacy 图标完整保留 Stitch 的轻微绿底质感。
source.save(OUT_DIR / "app_icon.png")

# 自适应前景只提取薄荷色 K。源图 K 的亮度远高于背景，阈值边缘做柔和 alpha，
# 再将整体缩至 82%，确保圆形/水滴形 launcher mask 不截断三笔 K。
rgb = source.convert("RGB")
pixels = list(rgb.get_flattened_data())
rgba = []
for r, g, b in pixels:
    luminance = (r * 299 + g * 587 + b * 114) // 1000
    alpha = max(0, min(255, (luminance - 105) * 9))
    # 保留源图薄荷绿，不把它扁平成白色或单一色。
    rgba.append((r, g, b, alpha))

mark = Image.new("RGBA", (N, N))
mark.putdata(rgba)
bbox = mark.getbbox()
if bbox is None:
    raise ValueError("could not extract K mark from source")
mark = mark.crop(bbox)

safe_size = int(N * 0.66)
mark.thumbnail((safe_size, safe_size), Image.Resampling.LANCZOS)
fg = Image.new("RGBA", (N, N), (0, 0, 0, 0))
fg.alpha_composite(mark, ((N - mark.width) // 2, (N - mark.height) // 2))
fg.save(OUT_DIR / "app_icon_fg.png")

print("icons written to", OUT_DIR)
print(" source", source.size)
print(" foreground mark", mark.size, "bbox", fg.getbbox())
