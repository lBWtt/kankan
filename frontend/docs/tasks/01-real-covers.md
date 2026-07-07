# 任务①：真实项目封面图（对齐原型的"编辑级"质感）

**先读** `docs/KANKAN_SPEC.md`（视觉真源 + 铁律 + 验收）。

## 目标
把项目卡 `project_card.dart` 的 `CustomPainter` 几何占位（`CoverArt`）换成**真实封面图**,
让"看看 / 收藏 / 发现"的列表有原型那种编辑级质感。

## 封面图从哪来
**你自己在网上找合适的图**（原型里那 16 张不用）。要求:
- 每张契合对应项目主题（如「Midjourney 国风电商图」→ 国风/电商视觉;「AI 会议纪要工具」→ 会议/效率视觉;「AI 出题助手」→ 教育视觉）。
- 用**稳定可直链的免费图源**（如 Unsplash 直链 `https://images.unsplash.com/...`、picsum 带 seed `https://picsum.photos/seed/xxx/800/600` 等）。别用会失效/防盗链的链接。
- 暖色调优先,和暖纸底 `#FBF9F4` 协调;避免大面积刺眼纯色。

## 做什么
1. **数据**：给 `lib/data/seed/mock_seed.dart` 的每个 `mockProjects` 配一张封面图 URL。
   - 有图项目已有 `resultData.media.first.url`（图片直链）——优先复用/替换成贴题的好图。
   - 无图项目：在其 `resultData.media` 塞一张 `MediaItem(type:'image', url: <封面URL>)`,或按需给封面用。
2. **渲染**（`project_card.dart` 的 `_Cover`）：
   - 有封面 URL → `Image.network(url, fit: BoxFit.cover, ...)` 渲染真图;
   - `loadingBuilder` → 显示现有 `CoverArt` 占位（加载中不空白）;
   - `errorBuilder` → 回退 `CoverArt`（断网/404 **不崩**）;
   - **不要引入新依赖**（用 `Image.network`,别上 `cached_network_image`）。
   - 保持统一比例（full 卡 16:9 或现有高度;compact 56×56）。
3. **详情页顶部 cover**（`detail_screen.dart` 的 `_DetailCover`）：同一张图,同样 network+回退占位。

## 铁律（照 SPEC）
暖纸底 / **coral 只给 take** / 无 emoji / 44pt / 零旁白 / 四态齐 / 禁不可变 sort / 禁 artifactType 分支。

## 验收（Claude 会跑）
- `flutter analyze` 0 error;能编译;
- 真图能出;**断网/坏链回退 CoverArt 不崩**;封面比例统一、和暖纸底协调。

## 别碰
`lib/core/theme/*`、`lib/core/network/*`。**不许整包重生成**,只改本任务相关文件（`mock_seed.dart` / `project_card.dart` / `detail_screen.dart`）。改完在本仓库开 PR。
