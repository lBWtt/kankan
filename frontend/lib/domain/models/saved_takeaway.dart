import 'package:freezed_annotation/freezed_annotation.dart';

part 'saved_takeaway.freezed.dart';

/// HANDOFF §6.3 「我拿走的」内容库 — 存下了得有地方找回。
///
/// Web 版完全没有这个,Flutter 端从零做对。按 文本/文件/链接 三档分类
/// (对应 TakeAction.takeKind == 'copy' / 'download' / GoAction 的 url):
///   - kind == 'text'   → 复制过的提示词 / 代码 / 配置(take copy)
///   - kind == 'file'   → 下载过的文件(take download)
///   - kind == 'link'   → 跳过的外链(go — 严格说不是"拿到手",但用户视角
///                        "我去过这",也纳入"我拿走的"找回库)
///
/// **铁律(HANDOFF §6.10):计数取真实数组长度,禁止 ×200 编造。**
/// savedTakeaways.length 就是"我拿走的"总数,me 屏 / library 屏直接读。
@freezed
abstract class SavedTakeaway with _$SavedTakeaway {
  const factory SavedTakeaway({
    /// 唯一 ID(由 projectId + actionIndex 拼成,保证可去重)
    required String id,

    /// 来源项目 ID
    required String projectId,

    /// 来源项目标题(冗余存储,避免每次 join)
    required String projectTitle,

    /// 来源项目领域(用于按领域筛选,可选)
    required String domain,

    /// 分类:'text' | 'file' | 'link'
    required String kind,

    /// 内容本体:
    ///   - kind == 'text'  → 复制的文本
    ///   - kind == 'file'  → 文件下载链接
    ///   - kind == 'link'  → 跳转的 URL
    required String source,

    /// 可选对象名(从 TakeAction.label / GoAction.label 来)
    String? label,

    /// 拿走时间(毫秒)
    required int savedAtMs,
  }) = _SavedTakeaway;
}
