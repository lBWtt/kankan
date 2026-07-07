import 'package:freezed_annotation/freezed_annotation.dart';

import 'action_item.dart';
import 'result_data.dart';

part 'project.freezed.dart';

/// HANDOFF §1 项目(重)—— 有成果 + 素材。进库、有详情页。
///
/// 与 Post(动态,轻)二分:纯文字心得只能发成 Post,不能发成 Project。
///
/// 关键字段:
///   - resultData:成果区(4 渲染器组合)— HANDOFF §2.1
///   - actions:动作区(3 原语任意组合)— HANDOFF §2.2
///   - tags:真实标签字段(Web 版没有 → 话题恒空,Flutter 从零做对)— HANDOFF §6.2
///   - authorNote:作者的话(空 → detail 整块隐藏)— HANDOFF §2.3
///
/// 计数铁律(HANDOFF §6.10):
///   - likes / comments / takeaways 是真实数字(由 mock seed 写死真实值,
///     不在 model 层做 ×200 放大;放大是 Web 版的罪,Flutter 不犯)。
///   - 真实场景下这些是后端返回的计数字段,这里 mock 直接给数。
@freezed
abstract class Project with _$Project {
  const factory Project({
    required String id,

    /// 标题
    required String title,

    /// 一句话价值(detail 页标题下显示)
    required String summary,

    /// 作者 ID
    required String authorId,

    /// 成果区(media/repo/io/text 组合)
    required ResultData resultData,

    /// 动作区(take/go/how 任意组合,一行一个)。空 → 动作区整块不显示。
    @Default([]) List<ActionItem> actions,

    /// 标签(HANDOFF §6.2 — Web 版没有,Flutter 从零做对)
    @Default([]) List<String> tags,

    /// 作者的话(夹在成果与动作之间)。空 → 整块隐藏(连标题)。
    String? authorNote,

    /// 领域(用于 kankan 屏筛选)— 'ai_image' / 'ai_video' / 'web' / 'app' /
    /// 'tool' / 'opensource' / 'prompt'
    required String domain,

    /// 点赞数(真实)
    @Default(0) int likes,

    /// 评论数(真实,与 comments 列表长度一致 — HANDOFF §6.10)
    @Default(0) int commentCount,

    /// 被拿走次数(take 成功 +1,HANDOFF §2.2)
    @Default(0) int takeawayCount,

    /// 仓库 star 数(repo 项目用,与 RepoInfo.stars 同源)
    @Default(0) int repoStars,

    /// 创建时间(毫秒)
    required int createdAtMs,
  }) = _Project;
}
