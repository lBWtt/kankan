import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/config/app_config.dart';
import '../../core/network/app_exception.dart';
import '../../core/theme/kk_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/kk_back_button.dart';
import '../../core/widgets/tappable.dart';
import '../../data/api/me_api.dart';
import '../../data/api/media_api.dart';
import '../../data/api/users_api.dart';
import '../../domain/models/models.dart';
import '../../providers/app_state_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/project_provider.dart';
import '../../router/routes.dart';
import '../shared/avatar.dart';

/// 资料编辑屏 — 编辑 'me' 的名字 / 简介 / 学校 / 年龄。
/// （关注领域已退到后台，不再作为用户可编辑维度。）
///
/// 入口: me 屏"编辑资料" or profile 屏 _isMe 时的"编辑资料"。
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
  ConsumerState<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends ConsumerState<ProfileEditScreen> {
  late TextEditingController _nameCtrl;
  late TextEditingController _handleCtrl;
  late TextEditingController _bioCtrl;
  late TextEditingController _schoolCtrl;
  late TextEditingController _ageCtrl;
  bool _ctrlsReady = false;

  /// 首次 build 时用 me 数据初始化 controller(避免在 initState 中读 ref)
  void _ensureCtrls(
    String? initialName,
    String? initialHandle,
    String? initialBio,
    String? initialSchool,
    int? initialAge,
  ) {
    if (_ctrlsReady) return;
    _nameCtrl = TextEditingController(text: initialName ?? '')
      ..addListener(_onCtrlChanged);
    _handleCtrl = TextEditingController(text: initialHandle ?? '')
      ..addListener(_onCtrlChanged);
    _bioCtrl = TextEditingController(text: initialBio ?? '')
      ..addListener(_onCtrlChanged);
    _schoolCtrl = TextEditingController(text: initialSchool ?? '')
      ..addListener(_onCtrlChanged);
    _ageCtrl = TextEditingController(text: initialAge?.toString() ?? '')
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
      _handleCtrl.dispose();
      _bioCtrl.dispose();
      _schoolCtrl.dispose();
      _ageCtrl.dispose();
    }
    super.dispose();
  }

  bool get _hasChanges {
    final current =
        ref.read(authProvider).currentUser ?? ref.read(userByIdProvider('me'));
    final nameChanged = _nameCtrl.text.trim() != (current?.name ?? '');
    final handleChanged =
        _handleCtrl.text.trim().toLowerCase() != (current?.handle ?? '');
    final bioChanged = _bioCtrl.text.trim() != (current?.bio ?? '');
    final schoolChanged = _schoolCtrl.text.trim() != (current?.school ?? '');
    final ageChanged = _ageCtrl.text.trim() != (current?.age?.toString() ?? '');
    return nameChanged ||
        handleChanged ||
        bioChanged ||
        schoolChanged ||
        ageChanged;
  }

  Future<void> _changeAvatar() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 88,
      maxWidth: 1200,
    );
    if (file == null || !mounted) return;
    try {
      final uploaded = await ref
          .read(mediaApiProvider)
          .uploadRecord(await file.readAsBytes());
      await ref.read(meApiProvider).updateProfile(avatarUrl: uploaded.url);
      final current = ref.read(authProvider).currentUser;
      if (current != null) {
        ref.read(authProvider.notifier).updateCurrentUser(
              name: current.name,
              avatar: uploaded.url,
              bio: current.bio,
              school: current.school,
              age: current.age,
            );
      }
      ref.invalidate(userByIdProvider('me'));
      if (mounted) _toast('头像已更新');
    } on AppException catch (e) {
      if (mounted) _toast('头像更新失败：${e.message}');
    }
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _toast('名字不能为空');
      return;
    }
    final bio = _bioCtrl.text.trim();
    final school = _schoolCtrl.text.trim();
    final ageText = _ageCtrl.text.trim();
    final age = ageText.isEmpty ? null : int.tryParse(ageText);
    if (ageText.isNotEmpty && (age == null || age < 1 || age > 120)) {
      _toast('年龄请输入 1–120');
      return;
    }
    // @handle：规范化（去 @、转小写）+ 前端先做一次格式校验，避免无谓请求。
    final cur = ref.read(authProvider).currentUser;
    final handleInput =
        _handleCtrl.text.trim().replaceAll('@', '').toLowerCase();
    final handleChanged = handleInput != (cur?.handle ?? '');
    if (handleChanged && handleInput.isNotEmpty) {
      final ok = RegExp(r'^[a-z][a-z0-9_]{2,29}$').hasMatch(handleInput);
      if (!ok) {
        _toast('用户名：小写字母/数字/下划线，字母开头，3–30 位');
        return;
      }
    }

    // 远端模式（useRemote + 已登录）：先 PATCH /me 真落库，失败如实报错、不 pop、不谎称已保存。
    // 关注领域已退到后台（不再作为用户可见/可编辑维度），此处不再传 interest_content_types。
    if (AppConfig.useRemote && ref.read(authProvider).isLoggedIn) {
      try {
        await ref.read(meApiProvider).updateProfile(
              nickname: name,
              // 只在真改了且非空时传 handle（撞名后端回 409 HANDLE_TAKEN）。
              handle: (handleChanged && handleInput.isNotEmpty)
                  ? handleInput
                  : null,
              bio: bio,
              school: school,
              age: age,
            );
        ref.invalidate(myCountsProvider); // me 页重读真兴趣
      } on AppException catch (e) {
        if (mounted) {
          _toast(e.code == 'HANDLE_TAKEN' ? '这个用户名已被占用' : '保存失败：${e.message}');
        }
        return;
      }
    }

    if (!mounted) return;
    // 本地 'me' 用户(mockUsers,appState.updateProfile 负责改写)驱动 profile/me 显示。
    ref
        .read(appStateProvider.notifier)
        .updateProfile(name: name, bio: bio.isEmpty ? null : bio);
    // 关键修复:me 页头部读的是 auth.currentUser.name,必须同步更新 authProvider,
    // 否则远程保存成功后名字不刷新(要退出重登才变)。
    ref.read(authProvider.notifier).updateCurrentUser(
          name: name,
          handle: (handleChanged && handleInput.isNotEmpty)
              ? handleInput
              : cur?.handle,
          bio: bio.isEmpty ? null : bio,
          school: school.isEmpty ? null : school,
          age: age,
        );
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
    // 远端登录用户的资料以 auth 状态为准，避免头像/昵称仍被旧 mock 的 me 覆盖。
    final me = ref.watch(authProvider).currentUser ??
        ref.watch(userByIdProvider('me'));
    _ensureCtrls(me?.name, me?.handle, me?.bio, me?.school, me?.age);

    // ── [ZCode] 删掉了 _statsSection（关注/粉丝/获赞是只读信息，不属于编辑页；
    //   跟 me 页读不同数据源导致数字不一致）。编辑页只保留可编辑字段。──

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
      // ── [ZCode] 整页重排为一张大卡：头像区 + 表单区 合为一体，干净留白 ──
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: KkSpacing.xxxl),
        child: Container(
          margin: const EdgeInsets.all(KkSpacing.lg),
          decoration: BoxDecoration(
            color: KkColors.bgCard,
            borderRadius: BorderRadius.circular(KkRadius.xl),
            boxShadow: KkElevation.card,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: KkSpacing.xl),
              _avatarSection(me),
              const SizedBox(height: KkSpacing.lg),
              const Divider(
                  indent: KkSpacing.xl,
                  endIndent: KkSpacing.xl,
                  color: KkColors.divider),
              const SizedBox(height: KkSpacing.lg),
              _formFields(),
            ],
          ),
        ),
      ),
    );
  }

  // ── [ZCode] 头像（96px）+ 名字 + 换头像 ──
  Widget _avatarSection(KkUser? me) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        KkAvatar(userId: 'me', user: me, size: 96),
        const SizedBox(height: KkSpacing.md),
        Text(me?.name ?? '未设置', style: KkType.h3),
        const SizedBox(height: 2),
        Tappable(
          onTap: _changeAvatar,
          borderRadius: BorderRadius.circular(KkRadius.pill),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: KkSpacing.md, vertical: KkSpacing.xs),
            child: Text('更换头像',
                style: KkType.bodySm.copyWith(color: KkColors.teal)),
          ),
        ),
      ],
    );
  }

  // ── [ZCode] 表单字段：填充式输入，label + bgSubtle 圆角底，无硬边框 ──
  Widget _formFields() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KkSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _field('名字', _nameCtrl, hint: '你的名字', maxLength: 20),
          const SizedBox(height: KkSpacing.lg),
          _field('用户名', _handleCtrl, hint: '例如 lin_deep', maxLength: 30),
          const SizedBox(height: 6),
          Text(
            '改名也不丢：别人可用 @用户名 搜到你。小写字母/数字/下划线，字母开头。',
            style: KkType.bodySm.copyWith(color: KkColors.t4, fontSize: 11),
          ),
          const SizedBox(height: KkSpacing.lg),
          _field('简介', _bioCtrl, hint: '一句话介绍自己', maxLength: 100, maxLines: 2),
          const SizedBox(height: KkSpacing.lg),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: _field('学校', _schoolCtrl, hint: '学校或院校', maxLength: 100),
              ),
              const SizedBox(width: KkSpacing.md),
              Expanded(
                child: _field(
                  '年龄',
                  _ageCtrl,
                  hint: '年龄',
                  maxLength: 3,
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
          const SizedBox(height: KkSpacing.lg),
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl,
      {String? hint,
      int maxLength = 50,
      int maxLines = 1,
      TextInputType? keyboardType}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _label(label),
      const SizedBox(height: KkSpacing.sm),
      _input(ctrl,
          hint: hint,
          maxLength: maxLength,
          maxLines: maxLines,
          keyboardType: keyboardType),
    ]);
  }

  Widget _input(TextEditingController ctrl,
      {String? hint,
      int maxLength = 50,
      int maxLines = 1,
      TextInputType? keyboardType}) {
    return Container(
      decoration: BoxDecoration(
        color: KkColors.bgSubtle,
        borderRadius: BorderRadius.circular(KkRadius.md),
      ),
      child: TextField(
        controller: ctrl,
        maxLength: maxLength,
        maxLines: maxLines,
        minLines: 1,
        keyboardType: keyboardType,
        style: KkType.body,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: KkType.body.copyWith(color: KkColors.t4),
          isDense: true,
          counterStyle: const TextStyle(
              color: KkColors.t3, fontSize: 11, fontFamily: 'JetBrainsMono'),
          contentPadding: const EdgeInsets.symmetric(
              horizontal: KkSpacing.md, vertical: KkSpacing.md),
          border: InputBorder.none,
        ),
      ),
    );
  }

  Widget _label(String text) {
    return Text(text, style: KkType.bodySm.copyWith(color: KkColors.t3));
  }
}
