import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../../core/theme/kk_colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/tappable.dart';
import '../../../domain/models/models.dart';

/// 视频块 — HANDOFF §2.1 视频优先:有视频,视频块排最上(真播放器,点击真能播)。
///
/// 用 video_player 包。初始化异步,加载中显示封面图 + 加载圈。
/// 点击播放/暂停,切换静音按钮。全屏 Phase 5 接(photo_view 不支持视频)。
class VideoBlock extends StatefulWidget {
  final MediaItem media;

  const VideoBlock({super.key, required this.media});

  @override
  State<VideoBlock> createState() => _VideoBlockState();
}

class _VideoBlockState extends State<VideoBlock> {
  VideoPlayerController? _controller;
  bool _initialized = false;
  bool _failed = false;
  bool _muted = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final c = VideoPlayerController.networkUrl(Uri.parse(widget.media.url));
      await c.initialize();
      c.setLooping(true);
      if (!mounted) return;
      setState(() {
        _controller = c;
        _initialized = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _togglePlay() {
    final c = _controller;
    if (c == null || !_initialized) return;
    setState(() {
      if (c.value.isPlaying) {
        c.pause();
      } else {
        c.play();
      }
    });
  }

  void _toggleMute() {
    final c = _controller;
    if (c == null) return;
    setState(() {
      _muted = !_muted;
      c.setVolume(_muted ? 0 : 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.media;
    final aspect = _initialized
        ? _controller!.value.aspectRatio
        : 16 / 9;

    return ClipRRect(
      borderRadius: BorderRadius.circular(KkRadius.md),
      child: AspectRatio(
        aspectRatio: aspect,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 封面 or 视频帧
            if (_initialized)
              FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _controller!.value.size.width,
                  height: _controller!.value.size.height,
                  child: VideoPlayer(_controller!),
                ),
              )
            else if (m.poster != null)
              Image.network(m.poster!, fit: BoxFit.cover)
            else
              Container(color: KkColors.bgSubtle),

            // 加载失败
            if (_failed)
              Container(
                color: KkColors.bgSubtle,
                alignment: Alignment.center,
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline, color: KkColors.t3, size: 32),
                    SizedBox(height: KkSpacing.sm),
                    Text('视频加载失败', style: KkType.bodySm),
                  ],
                ),
              ),

            // 加载中
            if (!_initialized && !_failed)
              const Center(child: CircularProgressIndicator(strokeWidth: 2)),

            // 点击播放/暂停遮罩(播放态整块移除控件,零残留 — HANDOFF §2.1
            // 无视频/播放中不渲染播放控件遮罩;tap 遮罩仍可暂停)
            if (_initialized)
              Positioned.fill(
                child: Tappable(
                  onTap: _togglePlay,
                  borderRadius: BorderRadius.zero,
                  child: ValueListenableBuilder<VideoPlayerValue>(
                    valueListenable: _controller!,
                    builder: (_, value, __) {
                      if (value.isPlaying) return const SizedBox.shrink();
                      return Center(
                        child: Container(
                          padding: const EdgeInsets.all(KkSpacing.md),
                          decoration: const BoxDecoration(
                            color: Color(0x80000000),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.play_arrow,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),

            // 右上:时长 or 静音按钮 + 全屏按钮
            if (_initialized)
              Positioned(
                top: KkSpacing.sm,
                right: KkSpacing.sm,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 静音
                    Tappable(
                      onTap: _toggleMute,
                      semanticLabel: _muted ? '取消静音' : '静音',
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: Color(0x80000000),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _muted ? Icons.volume_off : Icons.volume_up,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                    const SizedBox(width: KkSpacing.sm),
                    // Phase 5：全屏播放
                    Tappable(
                      onTap: _enterFullscreen,
                      semanticLabel: '全屏播放',
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: Color(0x80000000),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.fullscreen,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // 左下:时长标签
            if (m.durationSec > 0)
              Positioned(
                bottom: KkSpacing.sm,
                left: KkSpacing.sm,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0x80000000),
                    borderRadius: BorderRadius.circular(KkRadius.sm),
                  ),
                  child: Text(
                    _fmtDuration(m.durationSec),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontFamily: 'JetBrainsMono',
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _fmtDuration(int sec) {
    final m = sec ~/ 60;
    final s = sec % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  /// Phase 5：进入全屏播放。锁横屏 + push 全屏路由 + 退出恢复竖屏。
  void _enterFullscreen() {
    final c = _controller;
    if (c == null || !_initialized) return;
    final wasPlaying = c.value.isPlaying;
    c.pause(); // 内嵌暂停，全屏页接管播放
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _FullscreenVideoPage(
          url: widget.media.url,
          startPlaying: true,
        ),
      ),
    ).then((_) {
      // 退出全屏：恢复竖屏，内嵌恢复原播放态。
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      if (mounted && wasPlaying) c.play();
    });
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }
}

/// 全屏视频页：横屏 + 居中播放 + 点击播放/暂停 + 返回。
/// 退出时由调用方恢复竖屏（.then）。
class _FullscreenVideoPage extends StatefulWidget {
  final String url;
  final bool startPlaying;

  const _FullscreenVideoPage({required this.url, required this.startPlaying});

  @override
  State<_FullscreenVideoPage> createState() => _FullscreenVideoPageState();
}

class _FullscreenVideoPageState extends State<_FullscreenVideoPage> {
  VideoPlayerController? _controller;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      await c.initialize();
      c.setLooping(true);
      if (widget.startPlaying) c.play();
      if (!mounted) {
        c.dispose();
        return;
      }
      setState(() {
        _controller = c;
        _initialized = true;
      });
    } catch (_) {
      if (!mounted) return;
      Navigator.of(context).maybePop();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _togglePlay() {
    final c = _controller;
    if (c == null || !_initialized) return;
    setState(() {
      if (c.value.isPlaying) {
        c.pause();
      } else {
        c.play();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_initialized && _controller != null)
            Center(
              child: AspectRatio(
                aspectRatio: _controller!.value.aspectRatio,
                child: VideoPlayer(_controller!),
              ),
            )
          else
            const Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(Colors.white70),
              ),
            ),
          // 点击播放/暂停
          if (_initialized && _controller != null)
            Positioned.fill(
              child: Tappable(
                onTap: _togglePlay,
                borderRadius: BorderRadius.zero,
                child: ValueListenableBuilder<VideoPlayerValue>(
                  valueListenable: _controller!,
                  builder: (_, value, __) {
                    if (value.isPlaying) return const SizedBox.shrink();
                    return Center(
                      child: Container(
                        padding: const EdgeInsets.all(KkSpacing.lg),
                        decoration: const BoxDecoration(
                          color: Color(0x80000000),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.play_arrow,
                          color: Colors.white,
                          size: 48,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          // 返回按钮
          Positioned(
            top: MediaQuery.of(context).padding.top + KkSpacing.sm,
            left: KkSpacing.sm,
            child: Tappable(
              onTap: () => Navigator.of(context).maybePop(),
              semanticLabel: '退出全屏',
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Color(0x80000000),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
