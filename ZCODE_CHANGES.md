# ZCode 所有改动清单

> 日期：2026-07-14 ~ 2026-07-15
> 标记：`[ZCode]` 标注在代码中，`[Claude 原始]` 标注被替换的旧代码

---

## 一、功能改动

### 1. PostCard 底部加分享按钮
**文件**：`frontend/lib/features/shared/post_card.dart`

- 新增 `import 'share_sheet.dart'`
- 操作行从 `点赞 | 评论` 改为 `点赞 | 评论 | 分享`
- 点分享弹出分享海报（与详情页同款）

### 2. 看看「精选」Tab 改为"本周精选"
**文件**：`frontend/lib/features/kankan/kankan_screen.dart`

- 头部从单日 `"7月14日 · 周一" + "编辑精选"` 改为周范围 `"7月13日 — 7月19日" + "本周精选"`
- `featuredProjectsProvider` 加了本周时间窗过滤（周一 00:00 起）
- 新增 `kankanDomainFilterNotifier`（跨屏共享的领域筛选状态）

### 3. 我的页「关注的领域」点 chip 跳看看页
**文件**：`frontend/lib/features/me/me_screen.dart`

- 领域 chip 点击 → 跳到看看页并按该领域筛选（不再跳编辑资料）
- `kankan_screen.dart` 的领域筛选改为读跨屏 provider 而非本地 state

### 4. 我的页「调整」领域改为轻量 Sheet
**文件**：`frontend/lib/features/me/me_screen.dart`

- 点"调整"不再跳整页编辑资料，弹底部 sheet 只显示 7 个领域 pills
- 点保存 → 远程 PATCH /me（只传 interestContentTypes），不碰其他字段
- 新增 `_DomainEditSheet` widget

### 5. 我的页显示"我的动态"
**文件**：`frontend/lib/features/me/me_screen.dart`

- 新增 `_myContentSection` 替代旧的 `_myPostsSection`
- 两排：我发布的作品（横向项目卡）+ 我的动态（横向动态卡）
- 动态卡用 `_recentPostCard` + `_PostMiniCover`，不与作品卡混淆
- 动态不计入贡献卡

### 6. 编辑资料 UI 重做
**文件**：`frontend/lib/features/profile_edit/profile_edit_screen.dart`

- 输入框从 `OutlineInputBorder` 改为 `bgSubtle` 填充式圆角底，无硬边框
- 头像 80px → 96px，下面显示名字
- 头像+表单合并为一张大卡（分隔线区分），不再是两张分离卡片
- 新增学校、年龄字段
- **删除底部统计区**（关注/粉丝/获赞——只读信息不属于编辑页，且跟我的页数据源不一致）
- 保存时同步更新 `authProvider.currentUser`（修复编辑后名字不刷新的 bug）

### 7. 登录成功后自动跳转修复
**文件**：`frontend/lib/features/auth/login_screen.dart`

- `context.go(from)` → `GoRouter.of(context).go(from)`
- 避免 router redirect 与登录跳转的竞态

### 8. 发动态纯图无文可发送
**文件**：`frontend/lib/features/publish/compose_screen.dart`

- 无文字时 content 从 `" "`（空格，可能被后端 reject）改为 `"分享图片"`
- 输入框加 `autofocus: true`
- 发表按钮**始终可点**（不再灰掉），让用户看到具体报错
- 选图失败弹 toast（不再静默吞掉）
- 新增非 AppException 的兜底错误提示

---

## 二、删除的假功能/死代码

### 9. 设置页清理
**文件**：`frontend/lib/features/settings/settings_screen.dart`

| 删除项 | 原因 |
|---|---|
| 暖纸底纹开关 | 1800 颗微点肉眼不可见，无实际价值 |
| 导入数据 | 未实现，点了只弹 toast "将在后续版本支持" |
| 导出数据 | 同上 |
| 用户协议 | 同上 |
| 隐私政策 | 同上 |
| 开源致谢 | 同上 |
| 字号切换 toast | 分段控件已有视觉反馈，toast 多余 |

### 10. 噪声底纹移除
**文件**：`frontend/lib/core/theme/noise_background.dart`

- `NoiseBackground` 从 `ConsumerWidget` 退化为纯 `StatelessWidget`，直接返回 child
- `NoisePainter` 类（50 行 CustomPainter）整个删除
- 移除 `flutter_riverpod` 和 `app_state_provider` 依赖

### 11. 我的页贡献卡隐藏
**文件**：`frontend/lib/features/me/me_screen.dart`

- 贡献热力图全零（"近 26 周 · 共 0 次贡献"）→ 注释隐藏
- 后端 `/me/contributions` 接上后一行恢复

### 12. 我的页"关注的话题"隐藏
**文件**：`frontend/lib/features/me/me_screen.dart`

- `mockFollowedTopics` 是假数据 → 注释隐藏

---

## 三、视觉优化

### 13. 我的页区块标题加图标
**文件**：`frontend/lib/features/me/me_screen.dart`

- `_sectionRow` 新增 `icon` 参数
- "我发布的作品" 前加 `Icons.work_outline`
- "我的动态" 前加 `Icons.chat_outlined`

### 14. 空态改用 EmptyState 组件
**文件**：`frontend/lib/features/me/me_screen.dart`

- "还没有作品" / "还没有动态" 从 `Text("还没有作品")` 改为 `EmptyState` 居中组件

---

## 四、编译环境

### 15. Gradle 缓存移到纯英文路径
**文件**：`frontend/android/gradle.properties`（新增一行）

```
org.gradle.user.home=F:/gradle_cache
```

- 原因：Windows 用户名 `刘博文` 含中文，Gradle 9.1.0 + CMake 3.22.1 的 JSON 链路编码失败
- 效果：CMake `MalformedJsonException` 错误消失

---

## 五、改动文件清单

| 文件 | 改动行数（估） | 说明 |
|---|---|---|
| `frontend/lib/features/shared/post_card.dart` | +35 | 分享按钮 |
| `frontend/lib/features/kankan/kankan_screen.dart` | +60 / -10 | 本周精选 + 领域 provider |
| `frontend/lib/features/me/me_screen.dart` | +200 / -80 | 动态区 + 领域 sheet + 标题图标 + 空态 + 隐藏假数据 |
| `frontend/lib/features/profile_edit/profile_edit_screen.dart` | +120 / -150 | UI 重做 + 学校/年龄 + 删统计区 |
| `frontend/lib/features/settings/settings_screen.dart` | -50 | 删假按钮 + toast |
| `frontend/lib/features/publish/compose_screen.dart` | +15 | autofocus + 纯图发送 + 错误提示 |
| `frontend/lib/features/auth/login_screen.dart` | +2 / -2 | router.go 修复 |
| `frontend/lib/core/theme/noise_background.dart` | -60 / +10 | 移除噪点 |
| `frontend/android/gradle.properties` | +1 | Gradle 缓存路径 |
