// 这个文件是干什么的：候选「发布预览」+ 审核动作页。审核时**所见即所得**——按用户刷到时的
//   样子渲染（马甲作者头像+名、封面/图/视频、标题、正文、话题标签），只在顶部留一条细的
//   审核信息条（AI 分 + 风控标）+ 底部四键（通过/不推荐/暂存/编辑）。仅管理员构建可达。
// 如果它出错了：审核动作失败会弹提示；approve 准入不满足弹出缺项清单。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import '../../core/network/app_exception.dart';
import '../../core/theme/kk_colors.dart';
import '../../core/theme/tokens.dart';
import '../../data/api/admin_api.dart';
import 'admin_edit_sheet.dart';
import 'admin_labels.dart';

// 马甲名（仅预览用，让审核者看到"发出来像谁发的"；真实发布时后端随机派一个）。
const _personaNames = ['林深', '阿May', '老K', '拾光', '造物志'];
const _personaColors = [
  Color(0xFF1D9E75),
  Color(0xFFD85A30),
  Color(0xFF3478BE),
  Color(0xFFA57423),
  Color(0xFF7B58B0),
];

class AdminCandidateDetailScreen extends ConsumerWidget {
  final String candidateId;
  const AdminCandidateDetailScreen({super.key, required this.candidateId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(adminCandidateProvider(candidateId));
    return Scaffold(
      backgroundColor: KkColors.bg,
      appBar: AppBar(
        backgroundColor: KkColors.bg,
        elevation: 0,
        title: const Text('发布预览', style: KkType.h3),
      ),
      body: async.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: KkColors.teal)),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(KkSpacing.xl),
            child:
                Text('$e', textAlign: TextAlign.center, style: KkType.bodySm),
          ),
        ),
        data: (c) => _Preview(candidate: c),
      ),
      bottomNavigationBar: async.maybeWhen(
        data: (c) => _ActionBar(candidate: c),
        orElse: () => const SizedBox.shrink(),
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  final AdminCandidate candidate;
  const _Preview({required this.candidate});

  @override
  Widget build(BuildContext context) {
    final c = candidate;
    final idx = c.id.hashCode.abs() % _personaNames.length;
    final personaName = _personaNames[idx];
    final personaColor = _personaColors[idx];
    // 正文：简介 + 详情连起来当帖子正文（用户视角就是一段话）。
    final body = [
      if ((c.summary ?? '').isNotEmpty) c.summary!.trim(),
      if ((c.description ?? '').isNotEmpty) c.description!.trim(),
    ].join('\n\n');

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        // ── 审核信息条（唯一的后台元素，细、灰、克制）──
        _ReviewStrip(candidate: c),

        // ── 以下 = 用户刷到时看到的样子 ──
        Padding(
          padding: const EdgeInsets.all(KkSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 作者行（马甲）
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: personaColor,
                    child: Text(
                      personaName.substring(0, 1),
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 15),
                    ),
                  ),
                  const SizedBox(width: KkSpacing.sm),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(personaName,
                          style: KkType.body
                              .copyWith(fontWeight: FontWeight.w600)),
                      Text('刚刚',
                          style: KkType.mono
                              .copyWith(color: KkColors.t4, fontSize: 11)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: KkSpacing.md),

              // 媒体
              if (c.media.isNotEmpty) ...[
                _MediaSection(media: c.media),
                const SizedBox(height: KkSpacing.md),
              ],

              // 标题
              Text(c.title ?? '（无标题）', style: KkType.h2),
              if ((c.tagline ?? '').isNotEmpty) ...[
                const SizedBox(height: KkSpacing.xs),
                Text(c.tagline!,
                    style: KkType.body.copyWith(color: KkColors.t2)),
              ],

              // 正文
              if (body.isNotEmpty) ...[
                const SizedBox(height: KkSpacing.md),
                Text(body, style: KkType.body),
              ],

              // 作者补充说明（用户视角也看得到，保留）
              if ((c.aiImplementationHint ?? '').isNotEmpty) ...[
                const SizedBox(height: KkSpacing.md),
                Container(
                  padding: const EdgeInsets.all(KkSpacing.md),
                  decoration: BoxDecoration(
                    color: KkColors.mint,
                    borderRadius: BorderRadius.circular(KkRadius.md),
                  ),
                  child: Text(c.aiImplementationHint!,
                      style: KkType.bodySm.copyWith(color: KkColors.tealDark)),
                ),
              ],

              // 话题标签（#tag）
              if (c.tags.isNotEmpty) ...[
                const SizedBox(height: KkSpacing.md),
                Wrap(
                  spacing: KkSpacing.sm,
                  runSpacing: KkSpacing.xs,
                  children: c.tags
                      .map((t) => Text('#$t',
                          style: KkType.bodySm.copyWith(color: KkColors.teal)))
                      .toList(),
                ),
              ],
              const SizedBox(height: KkSpacing.xxl),
            ],
          ),
        ),
      ],
    );
  }
}

/// 顶部审核信息条：AI 分 + 风控标 + 平台，一行灰底，和用户视角明显区分。
class _ReviewStrip extends StatelessWidget {
  final AdminCandidate candidate;
  const _ReviewStrip({required this.candidate});

  @override
  Widget build(BuildContext context) {
    final c = candidate;
    final s = c.score;
    Color fg = KkColors.t3;
    if (s != null && s >= 80) {
      fg = KkColors.tealDark;
    } else if (s != null && s >= 65) {
      fg = KkColors.amber;
    }
    return Container(
      width: double.infinity,
      color: KkColors.bgSubtle,
      padding: const EdgeInsets.symmetric(
          horizontal: KkSpacing.lg, vertical: KkSpacing.sm),
      child: Row(
        children: [
          Text('审核信息',
              style: KkType.mono.copyWith(color: KkColors.t4, fontSize: 11)),
          const SizedBox(width: KkSpacing.md),
          Text(s == null ? 'AI 未评分' : 'AI $s 分',
              style: KkType.mono.copyWith(
                  color: fg, fontWeight: FontWeight.w700, fontSize: 12)),
          if (c.sourcePlatform != null) ...[
            const SizedBox(width: KkSpacing.md),
            Text(platformLabel(c.sourcePlatform!),
                style: KkType.mono.copyWith(color: KkColors.t4, fontSize: 11)),
          ],
          const Spacer(),
          ...c.riskFlags.take(2).map((f) => Padding(
                padding: const EdgeInsets.only(left: KkSpacing.xs),
                child: RiskChip(flag: f),
              )),
        ],
      ),
    );
  }
}

class _MediaSection extends StatelessWidget {
  final List<AdminMedia> media;
  const _MediaSection({required this.media});

  @override
  Widget build(BuildContext context) {
    final ordered = [
      ...media.where((m) => m.isVideo),
      ...media.where((m) => !m.isVideo),
    ];
    return Column(
      children: [
        for (final m in ordered) ...[
          if (m.isVideo)
            _AdminVideo(url: m.url)
          else
            ClipRRect(
              borderRadius: BorderRadius.circular(KkRadius.md),
              child: Image.network(
                m.url,
                fit: BoxFit.cover,
                width: double.infinity,
                errorBuilder: (_, __, ___) => Container(
                  height: 180,
                  color: KkColors.bgSubtle,
                  alignment: Alignment.center,
                  child: const Icon(Icons.broken_image_outlined,
                      color: KkColors.t4),
                ),
              ),
            ),
          const SizedBox(height: KkSpacing.sm),
        ],
      ],
    );
  }
}

/// 内嵌极简视频播放器（点击播放/暂停）。
class _AdminVideo extends StatefulWidget {
  final String url;
  const _AdminVideo({required this.url});
  @override
  State<_AdminVideo> createState() => _AdminVideoState();
}

class _AdminVideoState extends State<_AdminVideo> {
  VideoPlayerController? _c;
  bool _ready = false;
  bool _failed = false;

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
      if (!mounted) {
        c.dispose();
        return;
      }
      setState(() {
        _c = c;
        _ready = true;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return Container(
        height: 180,
        decoration: BoxDecoration(
          color: KkColors.bgSubtle,
          borderRadius: BorderRadius.circular(KkRadius.md),
        ),
        alignment: Alignment.center,
        child: const Text('视频加载失败', style: KkType.bodySm),
      );
    }
    if (!_ready || _c == null) {
      return Container(
        height: 180,
        decoration: BoxDecoration(
          color: KkColors.bgSubtle,
          borderRadius: BorderRadius.circular(KkRadius.md),
        ),
        alignment: Alignment.center,
        child: const CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(KkRadius.md),
      child: AspectRatio(
        aspectRatio:
            _c!.value.aspectRatio == 0 ? 16 / 9 : _c!.value.aspectRatio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            VideoPlayer(_c!),
            GestureDetector(
              onTap: () => setState(
                  () => _c!.value.isPlaying ? _c!.pause() : _c!.play()),
              child: ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: _c!,
                builder: (_, v, __) => v.isPlaying
                    ? const SizedBox.shrink()
                    : Center(
                        child: Container(
                          padding: const EdgeInsets.all(KkSpacing.md),
                          decoration: const BoxDecoration(
                            color: Color(0x80000000),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.play_arrow,
                              color: Colors.white, size: 32),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 底部审核动作栏：通过 / 不推荐 / 暂存 / 编辑。
class _ActionBar extends ConsumerStatefulWidget {
  final AdminCandidate candidate;
  const _ActionBar({required this.candidate});
  @override
  ConsumerState<_ActionBar> createState() => _ActionBarState();
}

class _ActionBarState extends ConsumerState<_ActionBar> {
  bool _busy = false;

  // action 返回成功后要 toast 的文案（approve 里据实际派到的马甲名动态生成）。
  Future<void> _run(Future<String> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    try {
      final okMsg = await action();
      ref.invalidate(adminQueueProvider);
      messenger.showSnackBar(SnackBar(content: Text(okMsg)));
      if (router.canPop()) router.pop();
    } on AppException catch (e) {
      if (!mounted) return;
      final problems = e.details?['problems'];
      if (e.code == 'PUBLISH_GATE_FAILED' && problems is List) {
        await showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('还不能通过'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: problems
                  .map((p) => Text('· $p', style: KkType.bodySm))
                  .toList(),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('知道了')),
            ],
          ),
        );
      } else {
        messenger.showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = ref.read(adminApiProvider);
    final id = widget.candidate.id;
    return Container(
      padding: EdgeInsets.fromLTRB(KkSpacing.md, KkSpacing.sm, KkSpacing.md,
          KkSpacing.sm + MediaQuery.of(context).padding.bottom),
      decoration: const BoxDecoration(
        color: KkColors.bgCard,
        border: Border(top: BorderSide(color: KkColors.divider)),
      ),
      child: _busy
          ? const SizedBox(
              height: 44,
              child: Center(
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: KkColors.teal)),
            )
          : Row(
              children: [
                _secondary('编辑', Icons.edit_outlined, () => _openEdit(context)),
                const SizedBox(width: KkSpacing.sm),
                _secondary('暂存', Icons.inventory_2_outlined,
                    () => _run(() async {
                          await api.park(id);
                          return '已暂存';
                        })),
                const SizedBox(width: KkSpacing.sm),
                _secondary('不推荐', Icons.block_outlined,
                    () => _confirmDiscard(context, api, id)),
                const SizedBox(width: KkSpacing.sm),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: KkColors.teal,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () => _run(() async {
                      final r = await api.approve(id);
                      // 显示实际随机派到的马甲名（预览页的名字只是样例，以此为准）。
                      return (r.personaName?.isNotEmpty ?? false)
                          ? '已发布 · 作者：${r.personaName}'
                          : '已通过并发布';
                    }),
                    child: const Text('通过'),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _secondary(String label, IconData icon, VoidCallback onTap) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: onTap,
          icon: Icon(icon, size: 22, color: KkColors.t2),
          constraints: const BoxConstraints(minWidth: 40, minHeight: 32),
          padding: EdgeInsets.zero,
        ),
        Text(label,
            style: KkType.mono.copyWith(fontSize: 11, color: KkColors.t3)),
      ],
    );
  }

  Future<void> _openEdit(BuildContext context) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: KkColors.bg,
      builder: (_) => AdminEditSheet(candidate: widget.candidate),
    );
    if (changed == true) {
      ref.invalidate(adminCandidateProvider(widget.candidate.id));
      ref.invalidate(adminQueueProvider);
    }
  }

  Future<void> _confirmDiscard(
      BuildContext context, AdminApi api, String id) async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('不推荐这条？'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: '原因（可选）'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确定',
                  style: TextStyle(color: KkColors.coralDark))),
        ],
      ),
    );
    if (ok == true) {
      await _run(() async {
        await api.discard(id, reason: controller.text.trim());
        return '已不推荐';
      });
    }
  }
}
