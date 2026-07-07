import 'package:freezed_annotation/freezed_annotation.dart';

part 'media_item.freezed.dart';

/// HANDOFF §2.1 成果区 media 渲染器 —— 图片/视频统一走这一个。
///
/// 视频优先:有视频排最上(真播放器,点击真能播)。
/// 照片做小红书式横向滑动轮播(swipe + 圆点 + 计数 + 统一比例 + lightbox)。
@freezed
abstract class MediaItem with _$MediaItem {
  const factory MediaItem({
    /// 'image' | 'video'
    required String type,

    /// 资源 URL(图片直链 / 视频直链 mp4)
    required String url,

    /// 视频:封面图 URL;图片:可为 null
    String? poster,

    /// 视频:时长(秒),用于显示 0:30 等;图片:0
    @Default(0) int durationSec,

    /// 可选描述(alt text,a11y 用)
    String? alt,
  }) = _MediaItem;
}
