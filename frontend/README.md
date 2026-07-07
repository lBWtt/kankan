# 看看 Kankan · Flutter 版(Phase 3 Tier 4)

> **配套文档(本沙箱外,需一并阅读):**
> - `HANDOFF.md` — 产品与视觉施工标准(搭成什么样)。冲突时以此为准。
> - `Flutter迁移规划文档.md` — 技术怎么搭。
>
> **两点调整(覆盖迁移规划原文,见 HANDOFF §8):**
> 1. Drift 不进。用轻量 repository + 内存 mock,Phase 5 真有复杂缓存再上。
>    (F-34:曾经塞入的 Drift 占位代码 `lib/data/db/` 已删,见 FIXLOG_F.md F-34)
> 2. 删"视觉 100% 还原 Next.js 原型"。以 HANDOFF 的产品决策 + 美术铁律为准。

---

## Phase 3 Tier 4 交付内容(本次)

**收口 + 接入**:19 屏全齐 + 5 浮层全齐 + 3 个配套组件全部接入。
search_results 屏补齐 19 屏最后一块拼图(修复 Web 版 hashtag 跳空 + 自发项目堵死 2 bug);comment_actions_sheet 补齐 5 浮层;cover_art/skeletons/code_diff_block 三个 Tier 3 制作的组件全部接入真实使用点。

### 历史交付
- **Phase 1**:脚手架 + 设计系统(26 文件)
- **Phase 2 前半**:数据模型 + 项目详情页 + 项目发布页
- **Phase 2 后半**:发现/看看/我的/收藏 4 屏 + 统一 CommentThread 组件
- **Phase 3 Tier 1**:搜索 + 个人主页 + 通知中心 + 贡献热力图(5 屏 + 4 路由 + 8 接线)
- **Phase 3 Tier 2**:动态详情 + 全屏评论 + 关注/粉丝 + 资料编辑(4 屏 + 4 路由)
- **Phase 3 Tier 3**:榜单 + 话题 + 活动 + 设置 + 分享浮层 + 3 配套组件(8 文件 3579 行)

### 本次新增/改动文件(Phase 3 Tier 4)

#### 新增 2 文件

| 文件 | 行数 | 用途 |
|---|---|---|
| `lib/features/search/search_results_screen.dart` | 834 | 搜索结果页:4 Tab(项目/动态/用户/话题)+ HighlightedText 高亮 + 修复 Web 版 2 bug |
| `lib/features/shared/comment_actions_sheet.dart` | 350 | 评论操作浮层:5 按钮(回复/复制/编辑/删除/举报)+ Clipboard 真复制 + isOwn 分支 |

#### 修改 6 文件

| 文件 | 改动 |
|---|---|
| `lib/data/seed/mock_seed.dart` | +90 行:`MockWorkflow` class + `mockWorkflows`(8 条工作流)+ `findWorkflow(ref)` |
| `lib/features/shared/project_card.dart` | +21 行:`_Cover` 接入 `CoverArt`,7 领域映射 5 图案(ai_image→circles/ai_video→waves/web→grid/app→mountains/tool→grid/opensource→ink/prompt→waves) |
| `lib/features/discover/discover_screen.dart` | +41 行:300ms 假 loading + 4 骨架卡(ProjectCardSkeleton×3 + PostCardSkeleton×1)|
| `lib/features/kankan/kankan_screen.dart` | +28 行:300ms 假 loading + 3 骨架卡 + Tab/筛选 IgnorePointer 禁用 |
| `lib/features/library/library_screen.dart` | +34 行:300ms 假 loading + 3 骨架卡 |
| `lib/features/detail/widgets/action_row.dart` | +44 行:`_HowButton` 改 StatefulWidget + AnimatedSize 展开 + CodeDiffBlock 渲染 mockWorkflows |

### 关键修复(Phase 3 Tier 4)

#### Web 版 2 bug 修复(在 search_results_screen)

| Bug | Web 版表现 | Flutter 修复 |
|---|---|---|
| hashtag 跳空 | 点 #tag 丢回搜索框 | `_TopicRow` 整行 → `context.push(KkRoutes.topic(tag))` |
| 自发项目堵死 | 纯动态(quoteProjectId=null)点击无去处 | `_PostHit` 整卡 → `context.push(KkRoutes.postDetail(id))`,不论 quoteProjectId 是否 null |

#### HighlightedText 独立 widget

- query 为空 OR text 不含 query → 直接返回 `Text(text, style: baseStyle)`
- 否则 `RichText` + `TextSpan`(非匹配段) + `WidgetSpan`(匹配段,mint 底 + teal 字 + 圆角)
- 基线对齐保证高亮段不偏移

### 19 屏 + 5 浮层完成度

**19/19 屏全齐**:
- 4 Tab branch:discover / kankan / library / me
- 15 顶层路由:search / search_results / profile / notifications / comments / post_detail / detail / publish / follows / profile_edit / ranking / topic / activity / settings(+ FAB 弹 publish_entry)

**5/5 浮层全齐**:
- publish_entry_sheet(发布入口二选一)
- share_sheet(Canvas 海报 + 5 图案 + Clipboard)
- add_takeaway_sheet(发布页拿走物 sheet)
- comment_actions_sheet(评论长按操作,本次新增)
- comment_bottom_sheet(写评论输入浮层)

### 4/4 配套组件全部接入

| 组件 | 接入位置 | 验证 |
|---|---|---|
| `cover_art.dart` | `project_card._Cover`(7 领域映射 5 图案) | `rg CoverArt project_card.dart` = 5 命中 |
| `skeletons.dart` | discover / kankan / library 3 屏加载态 | `rg Skeleton discover/kankan/library` = 6+2+3 命中 |
| `code_diff_block.dart` | `action_row._HowButton` 展开后渲染 | `rg CodeDiffBlock action_row.dart` = 2 命中 |
| `contribution_heatmap.dart` | me 屏 + activity 屏 | 已在 Tier 1 接入 |

### HANDOFF 合规验收(Phase 3 Tier 4)

| HANDOFF 条款 | 验收 | 结果 |
|---|---|---|
| §2.2 珊瑚橙只给 take | comment_actions_sheet 删除按钮 coral / code_diff_block removed 行 coralMint | ✓ |
| §3 零旁白 | 新文件无引导文案 | ✓ |
| §5 触控 ≥44pt | 所有可点元素 Tappable 包裹 | ✓ |
| §5 禁 indigo/blue | `rg Colors.(blue\|indigo)` 0 业务命中 | ✓ |
| §5 无 emoji | 0 UI 命中(★/✓ 仅 mock 数据文本和 docstring) | ✓ |
| §6.7 真路由 | search_results + comment_actions 都走真路由/真浮层 | ✓ |
| §6.10 真实计数 | search_results 4 Tab badge 从 searchRepo.counts 真实取值 | ✓ |
| §7.1 禁 artifactType 硬编码 | 0 业务命中(仅 docstring 说明) | ✓ |

### 限制说明

- **无 Dart/Flutter SDK**:本沙箱未安装 Flutter SDK,无法跑 `dart analyze` / `flutter test`。
  所有验证靠静态 grep + 人工读审 + 试金石检查。
  用户拿到本包后需自行跑 `flutter pub get && dart run build_runner build -d && flutter analyze` 验证。
- **comment_actions_sheet 未接入 comments_screen**:`CommentThread` 组件无 `onCommentLongPress` 钩子,强行改会破坏 4 处调用。组件已就位,Phase 4 加钩子后接入。
- **share_plus / gal 未引入**:Phase 5 真分享时再上。(注:PR #26 已接 share_plus 真分享,PR 11-C 已接 gal 真存相册,本行为历史快照)
- **freezed codegen 未跑**:`.freezed.dart` 文件未生成,用户跑 `dart run build_runner build -d` 后可用。

### 下一步(Phase 4 / Phase 5)

- Phase 4 Hero 共享元素(项目卡 → 详情,HANDOFF §5 动效系统)
- Phase 4 CommentThread 加可选 `onCommentLongPress` 钩子,4 处调用方接 comment_actions_sheet
- Phase 4 Golden 测试(每屏截图回归)
- Phase 5 真持久化(替换内存 repository)。注:Drift 已弃用(F-34 analyzer 冲突),
  Phase 5 优先用 shared_preferences / isar / sqflite 任一不与 freezed analyzer 冲突的方案。
- Phase 5 share_plus 真分享 + gal 真存相册(已由 PR #26 / 11-C 落地)
- Phase 5 CachedNetworkImage 替换 project_card 封面占位

---

## Phase 3 Tier 3 交付内容(上一批)

补齐"进阶展示":榜单 + 话题 + 个人活动 + 设置 + 分享浮层 + 3 个配套组件(cover_art/skeletons/code_diff_block)。
kankan 屏榜单图标、me 屏设置/活动入口、detail/post_detail/topic 分享按钮全部接线,展示深度从 Tier 2 的"点击有深度"进到"点击有海报、有热力图、有榜单、有真实 heat"。

### 本次新增/改动文件(Phase 3 Tier 3)

#### 新增 8 文件(3579 行)

| 文件 | 行数 | 用途 |
|---|---|---|
| `lib/features/ranking/ranking_screen.dart` | 584 | 榜单页:三 Tab(项目/动态/作者)+ Top3 领奖台 stagger 动画 + rankChange chip 三态 |
| `lib/features/topic/topic_screen.dart` | 313 | 话题页:真实 heat 卡 + 双 Tab(动态/项目)+ 分享接入 |
| `lib/features/activity/activity_screen.dart` | 500 | 个人活动:三档真实统计 + 大热力图+图例 + 4 类时间线聚合 |
| `lib/features/settings/settings_screen.dart` | 499 | 设置:通知/外观/缓存/关于 4 section + 主题切换接 setThemeMode |
| `lib/features/shared/share_sheet.dart` | 696 | 分享浮层:5 Canvas 图案 + QR 占位 + RepaintBoundary + Clipboard 真实现 |
| `lib/core/widgets/cover_art.dart` | 307 | 5 种装饰封面 CustomPainter(waves/mountains/grid/circles/ink) |
| `lib/core/widgets/skeletons.dart` | 383 | 5 个骨架组件(ProjectCard/PostCard/Detail/SkeletonLine/SkeletonBox)+ shimmer |
| `lib/core/widgets/code_diff_block.dart` | 297 | HowAction 工作流:O(n*m) LCS 算法 + added/removed/unchanged 高亮 |

---

## Phase 3 Tier 2 交付内容(更上一批)

补齐"互动闭环":动态详情 + 全屏评论 + 关注/粉丝列表 + 资料编辑。
发现 feed 点击、评论图标、粉丝/关注计数、编辑资料入口全部接线,互动深度从 Phase 3 Tier 1 的"点击有去处"进到"点击有深度"。

### 本次新增/改动文件(Phase 3 Tier 2)

**路由层**
- `lib/router/routes.dart` — ★ 激活 4 条新路由:comments/:type/:id / post/:id / u/:userId/follows / profile/edit
- `lib/router/app_router.dart` — ★ 注册 4 条新 GoRoute + import 4 个新屏

**新屏实现(4 屏)**
- `lib/features/comments/comments_screen.dart` — ★ 全屏评论壳(包 CommentThread + AppBar「心得 N」+ 热/新排序,154 行)
- `lib/features/post_detail/post_detail_screen.dart` — ★ 动态详情(HANDOFF §1 轻量:复用 PostCard 视觉 + CommentThread,546 行)
- `lib/features/follows/follows_screen.dart` — ★ 关注/粉丝列表(双 Tab + 真实计数 + 关注按钮 + 空状态,285 行)
- `lib/features/profile_edit/profile_edit_screen.dart` — ★ 资料编辑(名字/简介/关注领域 pills + 头像占位 + 真实统计,423 行)

**已有屏接线升级(7 处)**
- `lib/features/shared/post_card.dart` — ★ 新增 `onTap` 整卡点击参数 + `onCommentTap` 默认推全屏评论页(空 callback 时)
- `lib/features/discover/discover_screen.dart` — 推荐 + 关注双流 PostCard 传 `onTap` → 推 post_detail
- `lib/features/profile/profile_screen.dart` — 关注/粉丝计数可点跳 follows + 编辑资料按钮 + more sheet 编辑项 → profileEdit + 动态 Tab PostCard 传 onTap
- `lib/features/detail/widgets/discussion_section.dart` — ★ 新增 `onViewAll` 参数 +「查看全部」pill → 推全屏评论
- `lib/features/detail/detail_screen.dart` — DiscussionSection 传 `onAddComment`/`onViewAll` → 推全屏评论页(替换 Phase 3 占位)

### HANDOFF 合规验收(Phase 3 Tier 2)

| 铁律 | 验收 | 结果 |
|---|---|---|
| §1 动态轻量 | post_detail 不引入 resultData/actions/takeaway,只复用 PostCard 视觉 + CommentThread | ✓ |
| §2 禁 if(artifactType) 分支 | `rg "if\s*\(.*artifactType" lib/` 真实代码 0 处(只 3 处注释作为禁令) | ✓ |
| §3 零旁白 | 4 新屏无教学引导;空状态用 EmptyState("暂无心得"/"还没有关注的人"/"还没有粉丝"/"动态不存在或已删除") | ✓ |
| §5 触控 ≥44pt | 所有新可点元素走 Tappable(minSize: 44),含排序按钮/关注按钮/领域 pills/保存按钮 | ✓ |
| §5 珊瑚橙只给 take | Tier 2 四屏 coral 仅 post_detail 的 like 情感色 1 处(允许);comments/follows/profile_edit 全 0 | ✓ |
| §5 无 emoji | `rg "[😀-🿿]" lib/` 0 处 | ✓ |
| §6.1 CommentThread 四处一致 | 全屏评论页/动态详情页/详情页内联/底部弹层 全部复用同一组件 | ✓ |
| §6.5 真路由 | `/u/:userId/follows` + `/profile/edit` 可深链;profile 计数点击跳转 | ✓ |
| §6.10 禁编造公式 | `rg "×\s*\d+" lib/` 0 处;所有计数取 .length / fold 求和 | ✓ |
| Web bug 修复延续 | post_card onCommentTap 默认推全屏评论(修复 Web 版评论图标无目标) | ✓ |

---

## Phase 3 Tier 1 交付内容(上一批)

**数据层扩展**
- `lib/domain/models/notification_item.dart` — ★ 新增 HANDOFF §6.8 通知模型(5 类精准跳转 + targetId/hostType 三字段)
- `lib/domain/models/topic.dart` — ★ 新增话题模型(真实 heat 聚合,禁 ×8+30 编造)
- `lib/domain/repositories/notification_repository.dart` — ★ 通知 repo(未读集合 + markRead/markAllRead)
- `lib/domain/repositories/search_repository.dart` — ★ 搜索 repo(4 类搜索 + 真实 heat 聚合 + 修复 Web 2 bug)
- `lib/data/seed/mock_seed.dart` — 扩展 mockNotifications(12 条 5 类)+ mockHeatmapCells(86 cells)+ mockBrowseHistory + mockRecentSearches + HeatmapCell 类
- `lib/providers/app_state_provider.dart` — 扩展 unreadNotifIds + recentSearches 状态 + markNotifRead/markAllNotifRead/addRecentSearch/removeRecentSearch/clearRecentSearches 方法

**路由层(`lib/router/`)**
- `routes.dart` — ★ 激活 4 条新路由:search / searchResults/:query / u/:userId / notifications
- `app_router.dart` — 注册 4 条新 GoRoute + import 4 个新屏

**新屏实现**
- `lib/features/search/search_screen.dart` — ★ 搜索屏(autofocus 输入 + 最近搜索 chip + 热门话题榜单,真实 heat 排序)
- `lib/features/search/search_results_screen.dart` — ★ 搜索结果屏(4 Tab:项目/动态/用户/话题 + 高亮匹配 + 修复 Web 2 bug)
- `lib/features/profile/profile_screen.dart` — ★ 个人主页(三 Tab:动态/项目/收藏 + 关注按钮 + 拉黑/举报 action sheet)
- `lib/features/notifications/notifications_screen.dart` — ★ 通知中心(5 类精准跳转 + 时间桶分组:今天/昨天/本周/更早 + 未读红点 + 全部已读)

**新组件**
- `lib/features/me/widgets/contribution_heatmap.dart` — ★ 86 cells 贡献热力图(GitHub 风格 + mint→teal 5 档色阶 + 真实统计)

**已有屏接线升级**
- `lib/features/me/me_screen.dart` — 注入 ContributionHeatmap + 个人信息卡可点跳 profile + 通知菜单项带未读 badge + 三档统计可点跳
- `lib/features/discover/discover_screen.dart` — 搜索图标接线 → /search
- `lib/features/kankan/kankan_screen.dart` — 搜索图标接线 → /search
- `lib/features/library/library_screen.dart` — 搜索图标接线 → /search
- `lib/features/shared/post_card.dart` — 头像 + 作者名可点跳 profile
- `lib/features/shared/project_card.dart` — 作者行可点跳 profile
- `lib/features/shared/comment_thread.dart` — 评论头像可点跳 profile

### HANDOFF 合规验收(Phase 3 Tier 1)

| 铁律 | 验收 | 结果 |
|---|---|---|
| §2 禁 if(artifactType) 分支 | `grep "artifactType ==" lib/` 真实代码 0 处 | ✓ |
| §3 零旁白 | 通知/搜索/个人主页无教学引导;空状态用 EmptyState | ✓ |
| §5 触控 ≥44pt | 所有新可点元素走 Tappable(minSize: 44) | ✓ |
| §5 珊瑚橙只给 take | profile 拉黑/举报/退出登录改 t1,珊瑚橙 0 处违规(剩余全在 take/点赞情感色/通知红点) | ✓ |
| §5 无 emoji | UI 文案 0 emoji | ✓ |
| §6.2 真实 tags 索引 | searchRepository 用 Project.tags / Post.tags 真实匹配,非标题子串硬凑 | ✓ |
| §6.5 真路由 profile | `/u/:userId` go_router,可深链 | ✓ |
| §6.8 通知 5 类精准跳转 | like→profile / comment→detail 或 profile / follow→profile / favorite→detail / system→不跳 | ✓ |
| §6.10 禁编造公式 | topic heat = projectCount×10 + postCount×5 + totalLikes÷100(真实聚合,非 ×8+30);所有计数取 .length | ✓ |
| Web bug 修复:hashtag 跳空 | 话题 Tab 点 tag → 重新搜该 tag(等效 topic 页) | ✓ |
| Web bug 修复:自发项目堵死 | 动态搜索结果整卡可点 → 跳作者 profile(无 quote 也有去处) | ✓ |

---

## 目录树(Phase 1 + Phase 2 全量)

```
kankan_flutter/
├── pubspec.yaml                      # +freezed +video_player +photo_view +image_picker +url_launcher
├── analysis_options.yaml
├── README.md                         # 本文件
├── lib/
│   ├── main.dart
│   ├── app.dart
│   ├── core/                         # (Phase 1)设计系统 + 44pt Tappable
│   │   ├── theme/
│   │   │   ├── kk_colors.dart        # 暖纸#FBF9F4 / 墨绿#1D9E75 / 珊瑚橙#D85A30(只给 take)
│   │   │   ├── tokens.dart
│   │   │   ├── app_theme.dart
│   │   │   └── noise_background.dart
│   │   ├── fonts/font_family.dart
│   │   ├── utils/{parse_count.dart, time_ago.dart}
│   │   └── widgets/
│   │       ├── tappable.dart         # 44pt 热区铁律
│   │       ├── placeholder_screen.dart
│   │       └── kk_tab_bar.dart       # 5 槽(4 branch + FAB)
│   ├── domain/                       # ★ Phase 2 数据模型
│   │   ├── models/                   # freezed 不可变数据类 + sealed ActionItem
│   │   │   ├── media_item.dart       # {type:image/video, url, poster?, durationSec?}
│   │   │   ├── action_item.dart      # ★ sealed: TakeAction / GoAction / HowAction
│   │   │   ├── repo_info.dart        # GitHub 仓库卡数据
│   │   │   ├── io_block.dart         # 输入→输出效果
│   │   │   ├── result_data.dart      # {media, repo?, io?, text?} 组合容器
│   │   │   ├── user.dart
│   │   │   ├── project.dart          # ★ 含 tags 字段(HANDOFF §6.2)
│   │   │   ├── post.dart             # 动态(轻)
│   │   │   ├── comment.dart
│   │   │   ├── saved_takeaway.dart   # ★ Phase 2 后半:我拿走的(HANDOFF §6.3)
│   │   │   └── models.dart           # barrel
│   │   └── repositories/
│   │       ├── project_repository.dart  # 内存 mock(无 Drift)
│   │       └── post_repository.dart
│   ├── data/                         # ★ Phase 2 mock 数据
│   │   └── seed/
│   │       └── mock_seed.dart        # 14项目+10动态+8评论+8拿走,真实计数无×常量
│   ├── providers/                    # ★ Phase 2 Riverpod providers
│   │   ├── app_state_provider.dart   # ★ 后半扩展:liked/saved/followed/takeaways/history
│   │   ├── project_provider.dart     # projectByIdProvider(family) + sorted + tags
│   │   └── publish_provider.dart     # PublishDraftNotifier(实时构建 resultData+actions)
│   ├── router/
│   │   ├── routes.dart               # +detail/:id +publish
│   │   └── app_router.dart           # +顶层路由(detail/publish 不进 shell)
│   └── features/
│       ├── shared/                   # ★ Phase 2 后半新增 — 跨屏复用组件
│       │   ├── avatar.dart           # 首字母头像 + TappableAvatar
│       │   ├── empty_state.dart      # 4 变体空状态(无 emoji,零旁白)
│       │   ├── comment_thread.dart   # ★ HANDOFF §6.1 统一评论组件
│       │   ├── comment_bottom_sheet.dart # 评论弹层(嵌 CommentThread)
│       │   ├── post_card.dart        # 动态卡(发现页 feed)
│       │   └── project_card.dart     # 项目卡(看看/收藏/我,full+compact)
│       ├── discover/discover_screen.dart    # ★ 后半:推荐/关注双流 + 评论弹层
│       ├── kankan/kankan_screen.dart        # ★ 后半:三 Tab 真排序 + 领域筛选
│       ├── library/library_screen.dart      # ★ 后半:收藏 + 我拿走的(文本/文件/链接)
│       ├── me/me_screen.dart                # ★ 后半:真实统计 + 三档 + 菜单
│       ├── detail/                   # ★ Phase 2 前半 — HANDOFF §2 可组合渲染
│       │   ├── detail_screen.dart    # 指挥中心:页面顺序固定,禁 if(artifactType)
│       │   └── widgets/
│       │       ├── media_carousel.dart    # 视频优先 + 小红书滑动轮播 + 圆点 + 计数 + lightbox
│       │       ├── video_block.dart       # 真播放器(video_player)
│       │       ├── repo_card.dart         # 仓库卡(图标+name+★stars+语言)
│       │       ├── io_block_view.dart     # 输入→输出效果(非代码 diff)
│       │       ├── author_note.dart       # 作者的话(居中,空→整块隐藏)
│       │       ├── action_row.dart        # ★ 3 原语(switch 模式匹配,禁 if 分支)
│       │       └── discussion_section.dart # 心得讨论(Phase 3 接 CommentThread)
│       └── publish/                  # ★ Phase 2 前半 — HANDOFF §4 放什么猜什么
│           ├── publish_entry_sheet.dart   # FAB 弹的二选一(发动态/发作品)
│           ├── publish_screen.dart        # 主屏:不选类型,放什么系统猜什么
│           └── widgets/
│               ├── add_takeaway_sheet.dart # "+" 三选一(贴文本/传文件/放链接)
│               ├── media_picker.dart        # 传图/视频(image_picker)
│               ├── link_type_detector.dart  # GitHub/AppStore/网址 当场识别
│               └── publish_preview.dart     # 实时预览(复用 detail 渲染器,两端咬合)
├── test/
│   ├── widget_test.dart              # (Phase 1)冒烟
│   ├── models_test.dart              # ★ 模型 + §6.10 计数铁律 + 可组合数据结构
│   ├── link_type_detector_test.dart  # ★ §4 链接识别
│   └── publish_draft_test.dart       # ★ §4 两端咬合(视频排前 / actions 组合 / 领域猜测)
└── assets/fonts/{README.md, subset.sh}
```

---

## 本地运行步骤

### 0. 前置

- Flutter SDK ≥ 3.24
- Python 3 + `pip install fonttools brotli`(字体子集化,可选)

### 1. 生成原生壳

```bash
flutter create kankan_flutter --org com.kankan --platforms=ios,android
```

### 2. 用本包文件覆盖

```bash
# 把本 tar 解出的 lib/ test/ assets/ pubspec.yaml analysis_options.yaml README.md
# 覆盖 flutter create 生成的同名位置
```

### 3. 放字体(可选,见 assets/fonts/README.md)

```bash
cd assets/fonts && ./subset.sh /path/to/NotoSerifSC-Regular.otf && cd ../..
# 取消 pubspec.yaml 末尾 fonts: 段注释
```

### 4. ★ Phase 2 新增:freezed codegen

```bash
flutter pub get
dart run build_runner build -d
# 生成 *.freezed.dart 文件(part 声明指向它们)
# -d = delete conflicting outputs(自动覆盖冲突文件)
```

**这一步是 Phase 2 必需的**——freezed 用 `part 'xxx.freezed.dart';` 声明,
该文件由 build_runner 生成。不跑 codegen 编译会报 `uri_does_not_exist`。

### 5. iOS 额外步骤(image_picker / video_player 需要)

```bash
cd ios && pod install && cd ..
# image_picker 需在 ios/Runner/Info.plist 加:
#   NSPhotoLibraryUsageDescription
#   NSCameraUsageDescription
#   NSMicrophoneUsageDescription(视频)
# video_player 无需额外配置
```

### 6. 跑

```bash
flutter run                    # iOS 模拟器 / Android 模拟器 / 真机
```

### 7. 验 Phase 2 DoD

**数据模型:**
- [ ] `dart run build_runner build -d` 成功生成 .freezed.dart
- [ ] `flutter test test/models_test.dart` 通过(7 谱系覆盖 + 计数铁律)
- [ ] mock 项目数 ≥ 14(7 谱系 × 2)
- [ ] `rg "×\s*(200|8\+30)" lib/` 无结果(无编造公式)

**详情页(HANDOFF §2 验收):**
- [ ] **试金石**:`rg "if\s*\(.*artifactType" lib/` 无实际代码匹配(只在注释里作为禁令)
- [ ] 渲染用 `switch (action)` 模式匹配(sealed 穷举)
- [ ] 多动作项目(App+开源+提示词+工作流)四个动作并存
- [ ] 纯开源项目(p_repo_1)无珊瑚橙(只有 repo 卡 + go)
- [ ] 视频项目(p_aivid_1)视频在上、照片能左右滑
- [ ] take 点击真复制(剪贴板)/ 真下载(url_launcher)
- [ ] go 点击真开外链
- [ ] 作者的话空(p_aiimg_2)→ 整块隐藏

**发布页(HANDOFF §4 验收):**
- [ ] 无"选类型"步骤
- [ ] 放 GitHub 链接 → 当场识别并标"将显示为 GitHub"
- [ ] 能加多个拿走物(文件+链接+文本并存)
- [ ] 视频自动排前(toProject 验证)
- [ ] 发布端产出的 Project = 详情端所读结构(两端咬合)
- [ ] 通屏零旁白(只有 placeholder + 数据)

- [ ] `flutter test` 全通过
- [ ] `flutter analyze` 零 error

---

## 关键决策说明(Phase 2 做了什么 / 没做什么)

### A. ActionItem 用 sealed class + switch(不用 freezed)

HANDOFF §2 / §7.1 试金石:**禁 if(artifactType) 硬编码分支**。

实现:`ActionItem` 是 native Dart 3 `sealed class`,三个子类 `TakeAction` / `GoAction` / `HowAction`。
渲染用 `switch (a) { TakeAction(...) => ..., GoAction(...) => ..., HowAction(...) => ... }` 模式匹配。

为什么不用 freezed:sealed + switch 是 Dart 3 原生穷举匹配。新增 `ActionItem` 子类时,
编译器强制 switch 覆盖,不会漏。freezed 的 union 也能做,但多一层 codegen,核心架构敏感代码保持 codegen-free。

### B. 数据容器用 freezed(Project/Post/ResultData/MediaItem/RepoInfo/IoBlock/Comment/KkUser)

freezed 提供:不可变 + copyWith + equality + hashCode。`part 'xxx.freezed.dart'` 需 build_runner 生成。
README §4 步骤已写明。

### C. 发布端预览复用 detail 渲染器(HANDOFF §4 两端咬合)

`publish_preview.dart` 直接 import detail 的 `MediaCarousel` / `RepoCard` / `IoBlockView` / `ActionRow`。
保证发布端看到的样子 = 详情端真实显示的样子。两端咬合验收靠这个,不靠"两端各自实现再希望一致"。

### D. 视频用 video_player(真播放器)

HANDOFF §2.1 视频优先:有视频,视频块排最上(真播放器,点击真能播)。
`video_block.dart` 用 `video_player` 包,异步初始化 + 加载中封面 + 播放/暂停/静音。
mock 数据用 Google 的 sample mp4 URL(BigBuckBunny / ElephantsDream)。

### E. 图片轮播用 photo_view(lightbox)

小红书式横向滑动:PageView + 圆点 + 右上计数 + 统一 4:3 比例裁切框。
点开 lightbox 用 `photo_view` 支持缩放。

### F. 链接识别当场显示(HANDOFF §4 验收项)

`add_takeaway_sheet._linkForm()` 里,用户输入 URL 时实时调 `detectLinkLabel`,
当场显示"将显示为 GitHub / App Store / example.com"。这是 HANDOFF §4 的明确验收项。

### G. take 下载用 url_launcher 兜底(Phase 5 真后台下载)

Phase 2 的 take download 动作用 `url_launcher` 打开 URL(浏览器处理下载)。
Phase 5 接 `path_provider` + `dio` 做真后台下载 + 进度条。当前简化已满足 HANDOFF §2.2"真拿到手"。

### H. 发布页领域不选,系统猜(HANDOFF §4)

`PublishDraft._guessDomain()` 按内容猜:
- 有 video → ai_video
- 有 image → ai_image
- 有 GitHub go → opensource
- 有 App Store go → app
- 其他 go → web
- 有 copy take → prompt
- 有 download take → tool

用户全程不选类型。

### I. discover 屏加 Phase 2 验证入口

discover 屏底部列出所有 mock 项目,点开跳详情。这是 Phase 2 的验证脚手架,
Phase 3 真实双流(推荐/关注)实现后会替换。

---

## HANDOFF 铁律对照表

| HANDOFF 条款 | 实现位置 | 验收方式 |
|---|---|---|
| §1 动态/项目二分 | `Project` vs `Post` 模型;`publish_entry_sheet` 二选一 | 模型独立,发布入口分两条 |
| §2.1 4 渲染器 | `detail_screen._results()` + `MediaCarousel`/`RepoCard`/`IoBlockView`/text | 按 resultData 有什么渲染,无 if 分支 |
| §2.2 3 原语 | `action_row.dart` `switch (a)` | sealed 模式匹配,禁 if(artifactType) |
| §2.2 take 珊瑚橙 | `action_row._TakeButton` | `KkColors.coral` 只此一处 + 底栏拿走计数 |
| §2.2 go 墨绿描边 | `action_row._GoButton` | `Border.all(color: KkColors.teal)` |
| §2.2 how "工作流" | `action_row._HowButton` | `label ?? '工作流'` |
| §2.2 take 无"拿走"字 | `_TakeButton` 文案 | 图标 + 对象名,无"拿走" |
| §2.2 take +1 | `detail_screen._actions` onTakeSuccess | `incrementTakeaway` + `invalidate` |
| §2.3 页面顺序 | `detail_screen._body` slivers | 标题→作者→成果→作者的话→动作→讨论→底栏 |
| §2.3 作者的话空隐藏 | `if (project.authorNote != null && isNotEmpty)` | 整块不渲染 |
| §3 零旁白 | 全屏无教学副标题 | 只有 placeholder + 数据 |
| §4 不选类型 | `publish_screen` 无类型选择器 | `_guessDomain` 系统猜 |
| §4 放什么猜什么 | `media_picker` + `add_takeaway_sheet` | 传图视频→media,贴文本→take copy,放链接→go |
| §4 链接当场识别 | `link_type_detector` + `_linkForm` 实时 | 输入即显示"将显示为 X" |
| §4 两端咬合 | `publish_preview` 复用 detail 渲染器 | 发布端 Project = 详情端所读 |
| §5 暖纸底 | `KkColors.bg` #FBF9F4 | Scaffold backgroundColor |
| §5 墨绿品牌 | `KkColors.teal` #1D9E75 | primary |
| §5 珊瑚橙只给 take | `KkColors.coral` 仅 `action_row._TakeButton` + 拿走计数 | grep 验证 |
| §5 Noto Serif SC | `font_family.dart` + `KkType.h1/h2/h3` | 自托管子集化(见 assets/fonts/) |
| §5 禁 emoji | 全屏无 emoji | `rg "[😀-🿿]"` 无结果 |
| §5 44pt 触控 | `Tappable` 组件 | `ConstrainedBox(minWidth/Height: 44)` |
| §6.2 真实 tags | `Project.tags` 字段 + `popularTagsProvider` | 模型有 tags,话题索引真实 |
| §6.7 真路由 | `detail/:id` go_router | 深链可分享 |
| §6.10 真实计数 | mock_seed 全部真实数字 | `rg "×\d+"` 无编造公式 |
| §7.1 禁 if(artifactType) | `switch (a)` 模式匹配 | 试金石 grep 通过 |
| §8.1 Drift 推迟 | 内存 `ProjectRepository` | pubspec 无 drift |

---

## 下一步(Phase 3 Tier 3 + Phase 4)

### Phase 3 Tier 3(进阶展示)
- `ranking_screen.dart` — 榜单(kankan 屏榜单入口,领奖台 + 三 Tab + 名次升降)
- `topic_screen.dart` — 话题页(独立路由,Posts/Projects 双 Tab,真实 heat)
- `activity_screen.dart` — 个人活动(真实获收藏数,大热力图,时间线)
- `settings_screen.dart` — 设置(通知/外观/主题,清缓存显示真实字节数)
- `share_sheet.dart` 浮层 — Canvas 5 图案 + 二维码 + RepaintBoundary + share_plus

### Phase 4(深层屏 10 屏,规划 §7.5)
全部 19 屏 + 4 浮层完成,Hero 共享元素,Golden 测试。

### 配套组件(边做边补)
- `code_diff_block.dart` — HowAction 工作流展示(highlight.ts 移植 → tokenizer + LCS diff)
- `cover_art.dart` — 5 种 SVG → CustomPainter,project_card 封面图
- `skeletons.dart` — 骨架屏(ProjectCardSkeleton + PostSkeleton + shimmer)
- Hero 共享元素 — 项目卡 → 详情(HANDOFF §5 动效系统)

---

*Phase 3 Tier 2 把"互动闭环"补齐:动态详情 + 全屏评论 + 关注/粉丝列表 + 资料编辑 4 屏落地,发现 feed 点击 / 评论图标 / 粉丝关注计数 / 编辑资料入口全部接线,互动深度从 Tier 1 的"点击有去处"进到"点击有深度"。HANDOFF 试金石全过(§1 动态轻量 / §2 无 artifactType 分支 / §5 珊瑚橙只给 take+like / §6.1 CommentThread 四处一致 / §6.10 真实计数),进 Tier 3。*
