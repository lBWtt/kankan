# 任务⑨：评论长按菜单接线（编辑 / 删除 / 复制 / 打开链接）

**先读** `docs/KANKAN_SPEC.md`。目标：把**已存在但没接线**的评论长按菜单接通——长按评论 → 复制 / 编辑(自己) / 删除(自己) / 打开链接(含 URL 时)。原型的交互精致度。

## 现状（都已存在，只差接线）
- `comment_thread.dart`：`_CommentTile` 长按已触发 `onCommentLongPress(comment)`；线程 `_comments` 是内部可变 state（`late List<Comment> _comments = List.of(...)`），有 `onChanged` 回调；回复用 `_replyingTo` + 输入框模式。
- `comment_actions_sheet.dart`：`showCommentActionsSheet` 已支持 复制/编辑/删除/举报，**但按钮仅在调用方传对应回调时才渲染**（F-11）。现在调用方（comment_bottom_sheet / detail / comments_screen）只传空 `onCopy`，所以只显「复制内容」。
- **删除铁律已定**：删除按钮用 `KkColors.coral`（删自己评论 = take 语义例外，已实现）；举报不用 coral。

## 做什么：把菜单收进 CommentThread 内部，让它能改自己的 `_comments`
> 删除/编辑要改线程内部 state，而 sheet 现在从外部调用够不到 `_comments`。把长按 → sheet 的逻辑收进 `_CommentThreadState`，就能直接 setState。

1. 在 `_CommentThreadState` 加 `_showActions(Comment c)`，调 `showCommentActionsSheet`：
   - `isOwn: c.authorId == 'me'`
   - `onCopy`：sheet 内部已真实现（Clipboard），照旧。
   - `onDelete`（**仅 own**）：弹二次确认 `AlertDialog`（"删除这条心得？"，确认/取消）→ 确认后 `setState(() => _comments.removeWhere((x) => x.id == c.id))` + `widget.onChanged?.call()`。同时删该评论的楼中楼回复（若数据结构是嵌套，连子回复一起删）。
   - `onEdit`（**仅 own**）：进"编辑模式"——仿 `_replyingTo` 加一个 `_editingId`，输入框预填 `c.content`，提交时**替换**该评论 content（`_comments = _comments.map(...)`）而非新增；顶部提示条显示"编辑中"+取消。零旁白。
   - 打开链接：见第 2 点。
2. **打开链接**：若 `c.content` 含 URL（正则 `https?://\S+`），给 sheet 传一个新的可选参数（如 `String? linkUrl`），sheet 渲染「打开链接」动作 → `url_launcher` 的 `launchUrl`（已是依赖）。无 URL → 不显此项。
3. `_CommentTile` 的长按改为调用内部 `_showActions`（把现有 `onCommentLongPress` 作为可选 override：外部传了就用外部的，没传就用内部 `_showActions`，保持向后兼容）。
4. 调用方（comment_bottom_sheet 等）可以**删掉**它们现在传的空 `onCopy` lambda（改由内部处理），或保留不影响。

## 不做（避免 scope 膨胀）
- 举报评论（需举报屏，另开任务）。下载文件（评论是纯文本，无文件语义）。

## 铁律 + 约束（照 SPEC §6）
- **coral 只给 take** + 删除例外：删除按钮 coral，其余（复制/编辑/打开链接/取消）不用 coral。
- 无 emoji（用 Icon）。**零旁白**（确认框不写"删除后会怎样"，只列动作）。触控 ≥44pt。
- 删除要**二次确认**（防误删）。编辑走 `_editingId` 模式，别新开屏。
- **别动** `theme/*`、`network/*`、路由、其它屏、举报流程。主要改 `comment_thread.dart` + `comment_actions_sheet.dart`（加 `linkUrl` 参数）；调用方按需清理空回调。
- 在 main 最新基础上增量改，`flutter analyze` 0 error，开 PR。

## 交付
列出改了哪些文件，确认 analyze 无 error，开 PR 给链接。
