import 'package:freezed_annotation/freezed_annotation.dart';

import 'io_block.dart';
import 'media_item.dart';
import 'repo_info.dart';

part 'result_data.freezed.dart';

/// HANDOFF §2.1 成果区 = 4 渲染器的组合容器。
///
/// 这是可组合渲染的数据根基。detail 页按此结构有什么渲染什么:
///   - media 非空 → media 渲染器(视频优先 + 照片轮播)
///   - repo 非空  → repo 渲染器(仓库卡)
///   - io 非空   → io 渲染器(输入→输出效果)
///   - 三者皆空 + text 非空 → text 渲染器(纯心得正文)
///
/// 同一项目可同时有 media + repo + io(如:App 截图 + GitHub 仓库 + 提示词)。
/// **禁 if(artifactType) 硬编码分支** — 只认 resultData 有什么(HANDOFF §2 / §7.1)。
@freezed
abstract class ResultData with _$ResultData {
  const factory ResultData({
    /// 媒体列表(视频优先排序由 detail 渲染器负责)
    @Default([]) List<MediaItem> media,

    /// GitHub 等仓库卡(可选)
    RepoInfo? repo,

    /// 输入→输出效果(可选)
    IoBlock? io,

    /// 纯心得正文(media/repo/io 皆空时显示)
    String? text,
  }) = _ResultData;
}
