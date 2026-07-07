import 'package:flutter/foundation.dart';

/// HANDOFF §2.2 动作区 3 原语 —— sealed class(任意组合,一行一个)。
///
/// 这是可组合渲染的核心。detail 页按 `switch (action)` 模式匹配渲染,
/// **禁 if(artifactType) 硬编码分支**(HANDOFF §2 / §7.1 试金石)。
///
/// 颜色铁律(HANDOFF §5):
///   - TakeAction → 珊瑚橙 #D85A30(只此一处用珊瑚橙)
///   - GoAction   → 墨绿描边
///   - HowAction  → 次级墨绿文字,文案永远"工作流"
///
/// 按钮无"拿走"二字(HANDOFF §2.2):TakeAction 靠图标(下载/复制)表意。
sealed class ActionItem {
  const ActionItem();

  /// 可选标签。null 时按 primitive 推导默认(take 看 takeKind / go 看域名 / how 固定"工作流")。
  String? get label;
}

/// take — 真把东西拿到手(HANDOFF §2.2)。
///
/// [source]:
///   - takeKind == 'copy'    → 要复制的文本内容(prompt / 代码片段 / 配置)
///   - takeKind == 'download' → 要下载的文件 URL(.zip / .png / .pdf)
///
/// 珊瑚橙。按钮无"拿走"字,靠图标(复制 / 下载)表意。
/// 成功后 takeawayCount +1(HANDOFF §2.2,与点赞同源体感)。
///
/// [hint] (任务④):一句真实具体的「怎么用」(如「粘进对话框就能用」),
/// 在 ProjectCard take chip 显示成 `label · hint`。null 时只显 label(向后兼容)。
@immutable
class TakeAction extends ActionItem {
  final String source;
  final String takeKind; // 'copy' | 'download'
  final String? label;

  /// 任务④:真实具体的用法提示(「粘进…」「下载后…」),驱动「想拿走」意图。
  /// 不编造计数,只描述用法。null → 卡片只显 label。
  final String? hint;

  const TakeAction({
    required this.source,
    required this.takeKind, // 'copy' or 'download'
    this.label,
    this.hint,
  });
}

/// go — 导流(HANDOFF §2.2)。墨绿描边。行尾 ↗。真开外链(url_launcher)。
///
/// [url]: App Store / GitHub / 官网 / 实站。label 默认按域名推导(GitHub/App Store/官网)。
@immutable
class GoAction extends ActionItem {
  final String url;
  final String? label;

  const GoAction({required this.url, this.label});
}

/// how — 工作流(HANDOFF §2.2)。次级墨绿文字。文案**永远是"工作流"**。
///
/// [ref]: 工作流页面 ID 或外链。跳制作过程。
@immutable
class HowAction extends ActionItem {
  final String ref;
  final String? _label;

  const HowAction({required this.ref, String? label}) : _label = label;

  @override
  String? get label => _label ?? '工作流';
}
