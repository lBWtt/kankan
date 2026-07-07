import 'package:freezed_annotation/freezed_annotation.dart';

part 'topic.freezed.dart';

/// HANDOFF §6.2 + §6.10 话题 — 真实 heat 值,禁 ×8+30 编造公式。
///
/// Web 版重灾区:topic 屏 heat 字段用 `tag.length * 8 + 30` 编造,
/// 导致所有话题 heat 几乎一样(因为 tag 长度差异小)。
/// Flutter 端从零做对:heat 是真实聚合值 = 该 tag 下 Project 数 × 10 +
/// Post 数 × 5 + 总点赞数 ÷ 100(三方加权,反映真实热度)。
///
/// 计数铁律(HANDOFF §6.10):posts/projects 计数取真实数组长度。
@freezed
abstract class Topic with _$Topic {
  const factory Topic({
    /// 话题名(不含 #)
    required String tag,

    /// 真实热度(由 repository 聚合计算,不编造)
    @Default(0) int heat,

    /// 关联项目数(真实)
    @Default(0) int projectCount,

    /// 关联动态数(真实)
    @Default(0) int postCount,

    /// 该话题下所有项目的总点赞数(真实)
    @Default(0) int totalLikes,
  }) = _Topic;
}
