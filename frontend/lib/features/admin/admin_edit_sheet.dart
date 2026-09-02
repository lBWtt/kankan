// 这个文件是干什么的：审核页「编辑」底部弹层——人工补齐/修正候选文案（标题/亮点/简介/
//   详情/封面地址），PATCH 后状态自动→edited，常用于补上缺的封面让 approve 能过闸。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/app_exception.dart';
import '../../core/theme/kk_colors.dart';
import '../../core/theme/tokens.dart';
import '../../data/api/admin_api.dart';

class AdminEditSheet extends ConsumerStatefulWidget {
  final AdminCandidate candidate;
  const AdminEditSheet({super.key, required this.candidate});

  @override
  ConsumerState<AdminEditSheet> createState() => _AdminEditSheetState();
}

class _AdminEditSheetState extends ConsumerState<AdminEditSheet> {
  late final TextEditingController _title;
  late final TextEditingController _tagline;
  late final TextEditingController _summary;
  late final TextEditingController _desc;
  late final TextEditingController _cover;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final c = widget.candidate;
    _title = TextEditingController(text: c.title ?? '');
    _tagline = TextEditingController(text: c.tagline ?? '');
    _summary = TextEditingController(text: c.summary ?? '');
    _desc = TextEditingController(text: c.description ?? '');
    _cover = TextEditingController(text: c.coverMediaUrl ?? '');
  }

  @override
  void dispose() {
    _title.dispose();
    _tagline.dispose();
    _summary.dispose();
    _desc.dispose();
    _cover.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    // 只送有变化的字段（null 不动库里其它列）。
    final body = <String, dynamic>{};
    void put(String key, TextEditingController ctl, String? orig) {
      final v = ctl.text.trim();
      if (v != (orig ?? '')) body[key] = v.isEmpty ? null : v;
    }

    final c = widget.candidate;
    put('title', _title, c.title);
    put('tagline', _tagline, c.tagline);
    put('summary', _summary, c.summary);
    put('description', _desc, c.description);
    put('cover_media_url', _cover, c.coverMediaUrl);

    if (body.isEmpty) {
      nav.pop(false);
      return;
    }
    try {
      await ref.read(adminApiProvider).patch(c.id, body);
      messenger.showSnackBar(const SnackBar(content: Text('已保存')));
      nav.pop(true);
    } on AppException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (context, scroll) => Container(
          decoration: const BoxDecoration(
            color: KkColors.bg,
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(KkRadius.xl)),
          ),
          child: ListView(
            controller: scroll,
            padding: const EdgeInsets.all(KkSpacing.lg),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: KkColors.bd,
                    borderRadius: BorderRadius.circular(KkRadius.pill),
                  ),
                ),
              ),
              const SizedBox(height: KkSpacing.lg),
              const Text('编辑候选', style: KkType.h2),
              const SizedBox(height: KkSpacing.lg),
              _field('标题', _title),
              _field('一句话亮点', _tagline),
              _field('简介', _summary, maxLines: 4),
              _field('详情（可选）', _desc, maxLines: 3),
              _field('封面地址（补齐可过发布闸）', _cover),
              const SizedBox(height: KkSpacing.lg),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: KkColors.teal,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _busy ? null : _save,
                child: _busy
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('保存'),
              ),
              const SizedBox(height: KkSpacing.md),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController ctl, {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: KkSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: KkType.mono
                  .copyWith(color: KkColors.t3, fontWeight: FontWeight.w600)),
          const SizedBox(height: KkSpacing.xs),
          TextField(
            controller: ctl,
            maxLines: maxLines,
            style: KkType.body,
            decoration: InputDecoration(
              filled: true,
              fillColor: KkColors.bgCard,
              contentPadding: const EdgeInsets.all(KkSpacing.md),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(KkRadius.md),
                borderSide: const BorderSide(color: KkColors.bd),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(KkRadius.md),
                borderSide: const BorderSide(color: KkColors.teal),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
