import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/kk_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/parse_count.dart';
import '../../core/widgets/kk_back_button.dart';
import '../../core/widgets/tappable.dart';
import '../../domain/models/models.dart';
import '../../domain/repositories/post_repository.dart';
import '../../domain/repositories/project_repository.dart';
import '../../providers/app_state_provider.dart';
import '../../providers/project_provider.dart';
import '../../router/routes.dart';
import '../shared/avatar.dart';

/// 资料编辑屏 — 编辑 'me' 的名字 / 简介 / 关注领域 pills + 头像占位 + 真实统计。
///
/// 入口:
///   - me 屏"编辑资料"按钮(本任务不接线,主 agent 接)
///   - profile 屏 _isMe 时的"编辑资料"按钮
///
/// HANDOFF §3 零旁白:
///   - 字段名只 "名字/简介/关注领域",不写"请输入你的…"
///   - placeholder 事实:"一句话介绍自己" 是事实描述,可留
///   - snackbar 只事实:"已保存" / "名字不能为空" / "暂未接入"
///
/// HANDOFF §5 美术铁律:
///   - 珊瑚橙只给 take — 本屏无 take,保存按钮 / 选中 pill 均用 teal
///   - 全部触控元素 ≥44pt,统一走 Tappable
///   - 无 emoji
///
/// HANDOFF §6.10 真实计数:
///   - 关注/粉丝取 user.followingIds/followerIds 真实长度
///   - 获赞取该用户 projects.fold(likes) + posts.fold(likes),无 ×N 公式
///
/// 简化(Phase 3 Tier 2):
///   - KkUser freezed immutable 暂无 updateUser provider,
///     保存仅 snackbar "已保存" + pop(KkUser 实际未变)
///   - 头像更换占位,Phase 4 接 image_picker
///   - 关注领域 KkUser 无 interests 字段,UI-only 选中,
///     Phase 5 加字段后接 Drift
class ProfileEditScreen extends ConsumerStatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  ConsumerState<ProfileEditScreen> createState() =>
      _ProfileEditScreenState();
}

class _ProfileEditScreenState extends ConsumerState<ProfileEditScreen> {
  late TextEditingController _nameCtrl;
  late TextEditingController _bioCtrl;
  bool _ctrlsReady = false;

  /// 关注领域本地选中集合(KkUser 无 interests 字段,UI-only)
  Set<String> _selectedDomains = <String>{};
  Set<String> _initialDomains = const <String>{};

  /// 领域 pill 候选 — 对齐 kankan 屏 7 领域(去"全部")
  static const _domainOptions = <(String label, String value)>[
    ('AI图', 'ai_image'),
    ('AI视频', 'ai_video'),
    ('网页', 'web'),
    ('App', 'app'),
    ('工具', 'tool'),
    ('开源', 'opensource'),
    ('Prompt', 'prompt'),
  ];

  /// 首次 build 时用 me 数据初始化 controller(避免在 initState 中读 ref)
  void _ensureCtrls(String? initialName, String? initialBio) {
    if (_ctrlsReady) return;
    _nameCtrl = TextEditingController(text: initialName ?? '')
      ..addListener(_onCtrlChanged);
    _bioCtrl = TextEditingController(text: initialBio ?? '')
      ..addListener(_onCtrlChanged);
    _ctrlsReady = true;
  }

  void _onCtrlChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    if (_ctrlsReady) {
      _nameCtrl.dispose();
      _bioCtrl.dispose();
    }
    super.dispose();
  }

  bool get _hasChanges {
    final me = ref.read(userByIdProvider('me'));
    final nameChanged = _nameCtrl.text.trim() != (me?.name ?? '');
    final bioChanged = _bioCtrl.text.trim() != (me?.bio ?? '');
    final domainChanged = _selectedDomains.length != _initialDomains.length ||
        !_selectedDomains.containsAll(_initialDomains);
    return nameChanged || bioChanged || domainChanged;
  }

  void _toggleDomain(String value) {
    setState(() {
      if (!_selectedDomains.add(value)) {
        _selectedDomains.remove(value);
      }
    });
  }

  void _changeAvatar() {
    // Phase 4 接 image_picker
    _toast('暂未接入');
  }

  void _save() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _toast('名字不能为空');
      return;
    }
    final bio = _bioCtrl.text.trim();
    // F-3:写入内存 'me' 用户(mockUsers,appState.updateProfile 负责改写)。
    // domains 暂不持久化(KkUser 无 interests 字段,Phase 5 加字段后接)。
    ref
        .read(appStateProvider.notifier)
        .updateProfile(name: name, bio: bio.isEmpty ? null : bio);
    // 让依赖 userByIdProvider('me') 的屏(profile / me)重建显示新值。
    ref.invalidate(userByIdProvider('me'));
    _toast('已保存');
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(KkRoutes.discover);
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
        backgroundColor: KkColors.t1,
      ));
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(userByIdProvider('me'));
    _ensureCtrls(me?.name, me?.bio);

    final projectRepo = ref.watch(projectRepositoryProvider);
    final postRepo = ref.watch(postRepositoryProvider);

    // 真实计数(HANDOFF §6.10,无 ×N 公式)
    final following = (me?.followingIds ?? const <String>[]).length;
    final followers = (me?.followerIds ?? const <String>[]).length;
    final myProjects = projectRepo.byAuthor('me');
    final myPosts = postRepo.byAuthor('me');
    final totalLikes =
        myProjects.fold<int>(0, (s, p) => s + p.likes) +
            myPosts.fold<int>(0, (s, p) => s + p.likes);

    final hasChanges = _hasChanges;

    return Scaffold(
      backgroundColor: KkColors.bg,
      appBar: AppBar(
        backgroundColor: KkColors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: const KkBackButton(),
        titleSpacing: 0,
        title: Text('编辑资料', style: KkType.h3),
        actions: [
          Tappable(
            onTap: hasChanges ? _save : null,
            disabled: !hasChanges,
            borderRadius: BorderRadius.circular(KkRadius.pill),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: KkSpacing.lg,
                vertical: KkSpacing.sm,
              ),
              child: Text(
                '保存',
                style: TextStyle(
                  color: hasChanges ? KkColors.teal : KkColors.t4,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'NotoSerifSC',
                ),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: KkSpacing.xxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: KkSpacing.xl),
            _avatarSection(me),
            const SizedBox(height: KkSpacing.xl),
            _formCard(),
            const SizedBox(height: KkSpacing.lg),
            _statsSection(following, followers, totalLikes),
          ],
        ),
      ),
    );
  }

  // ── 头像区 ──
  Widget _avatarSection(KkUser? me) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        KkAvatar(userId: 'me', user: me, size: 80),
        const SizedBox(height: KkSpacing.md),
        Tappable(
          onTap: _changeAvatar,
          borderRadius: BorderRadius.circular(KkRadius.pill),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: KkSpacing.md,
              vertical: KkSpacing.xs,
            ),
            child: Text(
              '更换头像',
              style: KkType.bodySm.copyWith(color: KkColors.teal),
            ),
          ),
        ),
      ],
    );
  }

  // ── 表单卡 ──
  Widget _formCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: KkSpacing.lg),
      padding: const EdgeInsets.all(KkSpacing.lg),
      decoration: BoxDecoration(
        color: KkColors.bgCard,
        borderRadius: BorderRadius.circular(KkRadius.lg),
        border: Border.all(color: KkColors.bd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label('名字'),
          const SizedBox(height: KkSpacing.xs),
          _nameField(),
          const SizedBox(height: KkSpacing.lg),
          _label('简介'),
          const SizedBox(height: KkSpacing.xs),
          _bioField(),
          const SizedBox(height: KkSpacing.lg),
          _label('关注领域'),
          const SizedBox(height: KkSpacing.sm),
          _domainsWrap(),
        ],
      ),
    );
  }

  Widget _label(String text) {
    return Text(
      text,
      style: KkType.bodySm.copyWith(color: KkColors.t3),
    );
  }

  Widget _nameField() {
    return TextField(
      controller: _nameCtrl,
      maxLength: 20,
      style: KkType.body,
      decoration: InputDecoration(
        hintText: '名字',
        counterStyle: const TextStyle(
          color: KkColors.t3,
          fontSize: 11,
          fontFamily: 'JetBrainsMono',
        ),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: KkSpacing.md,
          vertical: KkSpacing.md,
        ),
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _bioField() {
    return TextField(
      controller: _bioCtrl,
      maxLength: 100,
      maxLines: 3,
      minLines: 2,
      style: KkType.body,
      decoration: InputDecoration(
        hintText: '一句话介绍自己',
        counterStyle: const TextStyle(
          color: KkColors.t3,
          fontSize: 11,
          fontFamily: 'JetBrainsMono',
        ),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: KkSpacing.md,
          vertical: KkSpacing.md,
        ),
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _domainsWrap() {
    return Wrap(
      spacing: KkSpacing.sm,
      runSpacing: KkSpacing.sm,
      children: [
        for (final (label, value) in _domainOptions)
          _domainPill(label, value, _selectedDomains.contains(value)),
      ],
    );
  }

  Widget _domainPill(String label, String value, bool selected) {
    // 修 bug:原用 Tappable(内部 Center+minWidth44)在 Wrap 里撑满整行 →
    // 7 个领域全宽堆叠成一长条(很丑)。改自适应 InkWell + 去掉 Center,
    // chip 贴合内容,Wrap 里紧凑多行流式。选中态保留 teal 填充。
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _toggleDomain(value),
        borderRadius: BorderRadius.circular(KkRadius.pill),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: KkSpacing.md,
            vertical: KkSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: selected ? KkColors.teal : KkColors.bgSubtle,
            borderRadius: BorderRadius.circular(KkRadius.pill),
            border: Border.all(
              color: selected ? KkColors.teal : KkColors.bd,
            ),
          ),
          child: Text(
            label,
            style: KkType.bodySm.copyWith(
              color: selected ? Colors.white : KkColors.t2,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  // ── 统计区(真实计数,只读,前两项可点跳 follows 屏)──
  Widget _statsSection(int following, int followers, int totalLikes) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: KkSpacing.lg),
      padding: const EdgeInsets.symmetric(
        horizontal: KkSpacing.lg,
        vertical: KkSpacing.lg,
      ),
      decoration: BoxDecoration(
        color: KkColors.bgCard,
        borderRadius: BorderRadius.circular(KkRadius.lg),
        border: Border.all(color: KkColors.bd),
      ),
      child: Row(
        children: [
          Expanded(
            child: _statBlock('关注', following, onTap: () {
              // 接通 follows 屏(?type= 深链到对应 tab,router 已解析 queryParameters['type'])
              context.push('${KkRoutes.follows('me')}?type=following');
            }),
          ),
          _vDivider(),
          Expanded(
            child: _statBlock('粉丝', followers, onTap: () {
              context.push('${KkRoutes.follows('me')}?type=followers');
            }),
          ),
          _vDivider(),
          Expanded(
            child: _statBlock('获赞', totalLikes),
          ),
        ],
      ),
    );
  }

  Widget _vDivider() {
    return Container(
      width: 1,
      height: 36,
      margin: const EdgeInsets.symmetric(horizontal: KkSpacing.sm),
      color: KkColors.divider,
    );
  }

  Widget _statBlock(String label, int value, {VoidCallback? onTap}) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(formatCount(value), style: KkType.monoLg),
        const SizedBox(height: 2),
        Text(
          label,
          style: KkType.bodySm.copyWith(color: KkColors.t3, fontSize: 11),
        ),
      ],
    );
    if (onTap == null) {
      return Center(child: content);
    }
    return Tappable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(KkRadius.md),
      child: Center(child: content),
    );
  }
}
