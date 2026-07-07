import 'package:freezed_annotation/freezed_annotation.dart';

part 'io_block.freezed.dart';

/// HANDOFF §2.1 成果区 io 渲染器 —— prompt/文本的"输入→输出**效果**"。
///
/// **不是代码 diff、不是 prompt 原文**(HANDOFF §2.1)。
/// 展示:输入(prompt / 配置)→ 输出(AI 生成的效果文本 / 渲染结果)。
@freezed
abstract class IoBlock with _$IoBlock {
  const factory IoBlock({
    /// 输入内容(prompt / 配置 / 命令)
    required String input,

    /// 输出效果(AI 生成的结果文本)
    required String output,

    /// 可选标题,如 "GPT-4o" / "Claude 3.5" / "Midjourney v6"
    String? model,

    /// 可选语言标签(若输入是代码)
    String? lang,
  }) = _IoBlock;
}
