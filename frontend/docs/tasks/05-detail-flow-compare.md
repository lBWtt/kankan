# 任务⑤：详情页「旧流程 → 新流程 + 省下时间」

**先读** `docs/KANKAN_SPEC.md`。目标：在详情页 how 动作展开的工作流里，代码 `before/after` diff **之上**，加一块「旧流程 → 新流程 + 省下时间」的叙事对比。这是原型第二强的「想做」钩子——让人直观看到"以前多麻烦、现在多快"。

> 现状：详情页 how 动作（`工作流` toggle）展开后渲染 `CodeDiffBlock`（`before`/`after` 代码对比，见 `lib/features/detail/widgets/action_row.dart` 的展开分支）。数据来自 `mockWorkflows`（`lib/data/seed/mock_seed.dart` 的 `MockWorkflow`）。本任务在其上加叙事流程块，**不动代码 diff**。

## Part A：扩 `MockWorkflow` 数据（内容，非计数，允许作者撰写）
给 `MockWorkflow` 加三个**可选**字段：
```dart
final List<String>? oldFlow; // 旧流程步骤,每步一句(如 '录音' / '听一遍记时间点' / '手动切')
final List<String>? newFlow; // 新流程步骤
final String? saved;         // 省下多少(如 '每期省 ~3 小时' / '每批省 ~30 分钟')
```
（`MockWorkflow` 是手写 class,加字段**不需要 build_runner**。）

给**至少 3 个**流程叙事说得通的工作流补真实内容（贴合该项目,别套话；不写数据不支持的假计数,只是"步骤 + 大致耗时"的合理描述）：
- `workflow_kling`（视频）→ old `['单条 prompt 出 5s','手动拼接多段','对轨调节奏']`, new `['storyboard 3 关键帧','逐帧 prompt 出 15s 连贯','一次成片']`, saved `'一条片省 ~2 小时'`
- `workflow_python_tool`（压缩脚本）→ old `['单线程逐张压','1000 张约 40 分钟','中途卡住重来']`, new `['8 进程并行','1000 张约 6 分钟','断点续传']`, saved `'每批省 ~30 分钟'`
- `workflow_gpt_review`（prompt 调优）→ old `['一句话丢给它','反复追问补充','结果泛泛']`, new `['一条结构化 prompt','四维度一次到位','直接可用']`, saved `'每次省 ~10 分钟'`

其余工作流 `oldFlow/newFlow` 留 null。

## Part B：渲染「流程对比」块（在 CodeDiffBlock 之上）
在 `action_row.dart` 工作流展开分支里，`CodeDiffBlock` **之前**插入：**当 `workflow.oldFlow != null && workflow.newFlow != null`** 时，渲染一个 `_FlowCompare` 小 widget：
- 两栏（或上下两段）：
  - 「旧流程」标题（`t3`）+ 步骤列表（每步前一个小灰点 `t3`,文字 `t2`,带删弱视觉——如整体 `t2`/略淡）。
  - 「新流程」标题（`teal` 或 `t1` 加粗）+ 步骤列表（每步前小圆点,文字 `t1`）。
- 中间/底部一个**醒目的「省下 {saved}」**：`KkColors.mint` 底 + `KkColors.teal` 文字 + `Icons.bolt`/`Icons.schedule` 图标,pill 圆角。**用 teal 不用 coral**（珊瑚橙只给 take,铁律 §6）。
- 版式克制,和详情页整体呼吸感一致（`KkSpacing.sm`/`md`）；两栏在窄屏用上下堆叠（别横向溢出）。
- `oldFlow/newFlow` 为 null → 这块整体不渲染（只显原来的 CodeDiffBlock,向后兼容）。

## 铁律 + 约束（照 SPEC §6）
- **coral 只给 take**（"省下"chip 用 teal/mint）。无 emoji（用 Icon,不用 😀）。零旁白。不出现「拿走」二字。
- 禁 `if(artifactType)` 硬编码分支。
- **别动** `lib/core/theme/*`、`network/*`、路由、其它屏、`CodeDiffBlock` 本身。
- 只改 `lib/features/detail/widgets/action_row.dart`（+ 新 `_FlowCompare` widget,同文件内即可）和 `lib/data/seed/mock_seed.dart`（`MockWorkflow` + 补内容）。
- 在 main 最新基础上增量改,`flutter analyze` 0 error,开 PR。

## 交付
列出改了哪些文件,确认 analyze 无 error,开 PR 给链接。
