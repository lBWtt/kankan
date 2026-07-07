import 'package:freezed_annotation/freezed_annotation.dart';

part 'repo_info.freezed.dart';

/// HANDOFF §2.1 成果区 repo 渲染器 —— GitHub 等仓库卡。
///
/// 显示:图标 + name + ★stars + 语言。
/// 纯导流项目(开源)只有 repo 卡 + 一个 go,**无珊瑚橙**(HANDOFF §2 验收)。
@freezed
abstract class RepoInfo with _$RepoInfo {
  const factory RepoInfo({
    /// 仓库短名,如 "flutter"
    required String name,

    /// 全名,如 "flutter/flutter"
    required String fullName,

    /// star 数(真实,禁编造 — HANDOFF §6.10)
    required int stars,

    /// 主语言,如 "Dart"
    required String language,

    /// 仓库 URL
    required String url,

    /// 可选描述
    String? description,
  }) = _RepoInfo;
}
