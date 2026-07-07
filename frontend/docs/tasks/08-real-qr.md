# 任务⑧：分享海报真二维码（扫得开）

**先读** `docs/KANKAN_SPEC.md`。目标：把分享海报里的**假二维码占位**换成**真·可扫描**二维码，让「扫码打开」名副其实。分享海报本身（`share_sheet.dart`）已做好且接线（详情/动态详情/话题页调用），本任务只动二维码这一处。

## 现状
- `lib/features/shared/share_sheet.dart` 海报底部：`CustomPaint(painter: _QrPlaceholderPainter(), size: Size(56,56))`（644 行的 `_QrPlaceholderPainter` 是画得像但**编码不了真实 URL**的假占位）。
- 海报接收 `widget.shareUrl`（真实 deep link）。

## 做什么
1. 加二维码依赖：`qr_flutter`（取当前 Flutter 3.44 兼容的最新版，如 `^4.1.0`）。若解析/编译不兼容，退用 `barcode_widget` 生成 QR。`flutter pub get`。
2. 把那处 `CustomPaint(... _QrPlaceholderPainter ...)` 换成真二维码，编码 `widget.shareUrl`：
   ```dart
   QrImageView(
     data: widget.shareUrl,
     size: 56,
     backgroundColor: Colors.white,
     // 深色模块,保证对比度可扫(别用 teal/珊瑚,扫不出)
     eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Color(0xFF16130F)),
     dataModuleStyle: const QrDataModuleStyle(color: Color(0xFF16130F)),
   )
   ```
3. **可扫描铁律**：二维码必须**深模块 + 白/浅底 + 足够 quiet zone**。若海报该区域是彩色/图案背景，把二维码包一个**白色圆角小盒**（`padding: 4~6`，`Colors.white`，`KkRadius.sm`）再放，保证对比度。别为了好看用低对比色导致扫不出。
4. 删掉 `_QrPlaceholderPainter`（不再引用 → 避免 dead code / unused_element 告警）。
5. 确认二维码在 `RepaintBoundary` 截图路径里能正常渲染（`QrImageView` 是普通 widget，可截图）。

## 铁律 + 约束（照 SPEC §6）
- 二维码是功能性元素，**对比度优先于配色**（深模块白底）；不套用 coral/teal 品牌色到模块上。
- 无 emoji。零旁白。不动海报其它部分（图案背景 / 文字 / 渠道按钮）。
- **别动** `theme/*`、`network/*`、路由、其它屏。只改 `share_sheet.dart` + `pubspec.yaml`（加依赖）。
- 在 main 最新基础上增量改，`flutter analyze` 0 error，开 PR。

## 交付
列出改了哪些文件（含 pubspec 加的依赖名+版本），确认 analyze 无 error，开 PR 给链接。
