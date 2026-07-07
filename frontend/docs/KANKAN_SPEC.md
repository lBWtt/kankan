# KANKAN 视觉与实现规格（SSOT）

> 本仓库唯一设计真源。视觉以 Web 原型 `kankaninteractive`（"看看 · AI 灵感工作台"）为准——
> 但 zai 打不开那个原型文件,所以下面把它的设计**编码成规格**,zai 照本文件做即可。
> 分工:**zai 出 90% UI；Claude 负责验收 + 微调 + 美感 + token/网络层；lbw 终审视觉。**
> 每个任务在 `docs/tasks/` 下,zai 读 main 最新 + 本 SPEC + 任务文件,改完开 PR。

## 1. 颜色（取自原型,已在 lib/core/theme/kk_colors.dart）
- 底:`bg #FBF9F4` / `bgSubtle #F5F3EE` / 卡片 `#FFFFFF` / 边框 `bd #E8E2D6`
- 品牌:`teal #1D9E75` / mint `#E1F5EE` / tealDark `#0F6E56`
- **coral #D85A30 只给 take（拿走/素材）**,别处禁用
- 点赞:`like #E0245E`（心用这个,不是 coral）
- 榜单:`gold #B68A2E` / `silver #9F9B92` / `bronze #B97F4F`；repo⭐:`amber #A57423`
- 文字:`t1 #16130F` / `t2 #6B6862` / `t3 #A39E96`

## 2. 阴影 / 圆角（已对齐原型,在 tokens.dart，勿改）
- 卡片阴影 `KkElevation.card` = `0 1px 2px rgba(22,19,15,.05)` + `0 12px 28px -18px rgba(22,19,15,.24)`
- 圆角:卡片 `KkRadius.lg`(16) / 胶囊 `pill`(999) / sheet 顶 `xl`(20)
- Feed 行（分隔线式）**不用阴影**；只有独立卡片用。

## 3. 深色模式（原型暗值,接 dark 主题时用）
- `bg #1A1714` / card `#232019` / bd `#2C2820` / teal `#2EBE8A` / coral `#E07349`

## 4. 字体
标题 Noto Serif SC；数字/计数/时间/代码 JetBrains Mono；正文系统 sans。走 `KkType`。

## 5. 四态铁律（任何"要数据"的界面必须齐）
loading=骨架(`skeletons.dart`,不用转圈) / error=一句话+重试 / empty=`EmptyState`(零旁白) / data。

## 6. 铁律（违反即打回）
1. 详情/发布渲染**禁 `if(artifactType==...)` 硬编码分支**——只认 resultData 有什么。
2. **coral 只给 take**；点赞用 like 色。
3. 想看怎么做（how-to-interest）**游客可用**,不设登录墙。
4. 计数是真实值,禁 `×常量` 编造。
5. **禁对 `List.unmodifiable`/repo `.all()` 原地 `..sort`**,先 `.toList()`。
6. 触控 ≥44pt（`Tappable`）；UI 无 emoji；**零旁白**（无教学副标题）。

## 7. 验收（Claude 跑）
- `flutter analyze` 0 error；`flutter build web` 通过 / 能跑。
- `rg "if\s*\(.*artifactType"` 0 命中；`rg "Colors\.(blue|indigo)"` 0；无 emoji。
- 新数据屏四态齐；触控走 Tappable。
- 视觉:对齐原型（Claude 结构级 + lbw 终审）。

## 8. zai 边界（别碰）
`lib/core/theme/*`（阴影/色板/字号 token,Claude 维护）、`lib/core/network/*`、`lib/data/api|dto`、`lib/providers/remote_*`。
**不许整包重生成**——在 main 最新基础上增量改,只动任务范围内文件。
