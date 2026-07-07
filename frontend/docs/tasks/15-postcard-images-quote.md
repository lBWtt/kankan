# 任务⑮：动态卡多图网格 + 引用项目卡精修

**先读** `docs/KANKAN_SPEC.md`。目标：让发现页动态卡（`post_card.dart`）**渲染配图**（现在完全没显 `post.media`！）+ 把引用项目卡做成浅绿底 + 分类徽标。质量标杆＝web 原型的动态页（多图网格 + 浅绿引用卡）。

## A. 动态配图网格（当前缺失，必做）
现状：`Post` 有 `media: List<MediaItem>` 字段，但 PostCard **根本没渲染图**（只画 作者行 + 正文 + 标签 + 引用 + 操作行）。补上，放在**正文下方、引用卡上方**：
- `post.media` 非空 → 按张数布局（小红书/朋友圈式）：
  - **1 张** → 单张大图（约 4:3 或 16:9，圆角 `KkRadius.md`）。
  - **2 张** → 并排两张（各 1:1，中间 `KkSpacing.xs` 间距）。
  - **3 张** → 一行三张（各 1:1）。
  - **4–9 张** → 3 列九宫格（各 1:1，间距 `KkSpacing.xs`）。
  - 超过 9 张只显前 9 张（最后一张叠「+N」浅色遮罩，可选）。
- 每张：`Image.network`（`loadingBuilder`/`errorBuilder` 回退 `CoverArt`，同 project_card 的封面套路），圆角，`BoxFit.cover`。
- 视频类型（`type=='video'`）叠 play 图标。
- 点图可选打开 lightbox（复用 `photo_view`，同详情页轮播）；不做也行，先把网格显出来。

## B. 引用项目卡精修（`_QuoteProject`）
现状：`bgSubtle` 中性底 + `bd` 边，无分类徽标。改成原型样式：
- 底色改**浅绿**（`KkColors.mint`）+ 细边或无边，圆角 `KkRadius.md`。
- 左：被引用项目的小封面/图标（现有 40×40）；中：项目名（`t1` 加粗）+ 作者 `@handle`（`t3`，若有）。
- **右上角加分类徽标**：项目 `domain` → 中文 label（AI图/AI视频/网页/App/工具/开源/Prompt，映射同 me 页 `_domainLabel`）+ teal 描边 pill（`mint` 或透明底 + `teal` 边 + `teal` 文字）。
- 整卡点击仍跳被引用项目详情（现有逻辑保留）。

## 铁律 + 约束（照 SPEC §6）
- coral 只给 take（本任务不涉及，全程别用 coral）。无 emoji（用 Icon）。零旁白。触控 ≥44pt。
- 禁 `if(artifactType)` 硬编码（按 media 有什么显什么 / 张数分支是布局不是类型硬编码，OK）。
- **别动** `theme/*`、`network/*`、后端接入文件、路由、其它屏、Post 模型。
- 只改 `post_card.dart`（+ 若需可加私有 `_ImageGrid` widget 同文件内）。mock 帖子已有 media，不够生动可在 `mock_seed.dart` 给几条帖子补 2–3 张图（内容，不算编造计数）。
- 在 main 最新基础上增量改，`flutter analyze` 0 error，开 PR。

## 交付
列出改了哪些文件，确认 analyze 无 error，开 PR 给链接。
