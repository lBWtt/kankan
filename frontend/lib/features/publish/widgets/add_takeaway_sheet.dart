import 'package:flutter/material.dart';

import '../../../core/theme/kk_colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/tappable.dart';
import '../../../domain/models/models.dart';
import 'link_type_detector.dart';

/// "+" 底部 sheet 三选一 — HANDOFF §4:
/// "+"点开底部 sheet 三选一(贴文本/传文件/放链接),"再加一样"可重复 → 多个素材。
///
/// 每选一样 → 产出 TakeAction(copy/download)或 GoAction → 加入 publish_draft.actions。
/// 任意组合,可 2 个 go + 1 个 take + 1 个 how(测试用 how 暂不在此加,Phase 3 接)。
class AddTakeawaySheet extends StatefulWidget {
  final void Function(ActionItem) onAdded;

  const AddTakeawaySheet({super.key, required this.onAdded});

  @override
  State<AddTakeawaySheet> createState() => _AddTakeawaySheetState();
}

class _AddTakeawaySheetState extends State<AddTakeawaySheet> {
  _Mode _mode = _Mode.menu;

  void _backToMenu() => setState(() => _mode = _Mode.menu);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: KkSpacing.xl,
        right: KkSpacing.xl,
        top: KkSpacing.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + KkSpacing.xl,
      ),
      child: switch (_mode) {
        _Mode.menu => _menu(),
        _Mode.text => _textForm(),
        _Mode.file => _fileForm(),
        _Mode.link => _linkForm(),
      },
    );
  }

  // ── 三选一菜单 ──
  Widget _menu() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: KkSpacing.lg),
            decoration: BoxDecoration(
              color: KkColors.t4,
              borderRadius: BorderRadius.circular(KkRadius.pill),
            ),
          ),
        ),
        const Text('素材', style: KkType.h2),
        const SizedBox(height: KkSpacing.lg),
        _option(
          icon: Icons.text_snippet_outlined,
          title: '贴文本',
          hint: '提示词 / 代码 / 配置 → 复制',
          onTap: () => setState(() => _mode = _Mode.text),
        ),
        _option(
          icon: Icons.attach_file_outlined,
          title: '传文件',
          hint: '脚本 / 压缩包 → 下载',
          onTap: () => setState(() => _mode = _Mode.file),
        ),
        _option(
          icon: Icons.link_outlined,
          title: '放链接',
          hint: 'GitHub / App Store / 网址 → 跳转',
          onTap: () => setState(() => _mode = _Mode.link),
        ),
      ],
    );
  }

  Widget _option({
    required IconData icon,
    required String title,
    required String hint,
    required VoidCallback onTap,
  }) {
    return Tappable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(KkRadius.md),
      padding: const EdgeInsets.symmetric(
        vertical: KkSpacing.md,
        horizontal: KkSpacing.md,
      ),
      child: Row(
        children: [
          Icon(icon, color: KkColors.teal, size: 22),
          const SizedBox(width: KkSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    style: KkType.body.copyWith(fontWeight: FontWeight.w600)),
                Text(hint, style: KkType.bodySm),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: KkColors.t3, size: 20),
        ],
      ),
    );
  }

  // ── 贴文本 ──
  Widget _textForm() {
    final ctrl = TextEditingController();
    final labelCtrl = TextEditingController();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Tappable(
              onTap: _backToMenu,
              child: const Icon(Icons.arrow_back,
                  color: KkColors.t1, size: 22),
            ),
            const SizedBox(width: KkSpacing.md),
            const Text('贴文本', style: KkType.h3),
          ],
        ),
        const SizedBox(height: KkSpacing.lg),
        TextField(
          controller: ctrl,
          maxLines: 6,
          minLines: 3,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '粘贴内容…',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: KkSpacing.sm),
        TextField(
          controller: labelCtrl,
          decoration: const InputDecoration(
            hintText: '对象名(可选,如 提示词 / 安装命令)',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: KkSpacing.lg),
        _confirmButton(
          label: '加为「复制」',
          onTap: () {
            final text = ctrl.text.trim();
            if (text.isEmpty) return;
            widget.onAdded(TakeAction(
              source: text,
              takeKind: 'copy',
              label: labelCtrl.text.trim().isEmpty
                  ? null
                  : labelCtrl.text.trim(),
            ));
            Navigator.pop(context);
          },
        ),
      ],
    );
  }

  // ── 传文件 ──
  Widget _fileForm() {
    final urlCtrl = TextEditingController();
    final labelCtrl = TextEditingController();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Tappable(
              onTap: _backToMenu,
              child: const Icon(Icons.arrow_back,
                  color: KkColors.t1, size: 22),
            ),
            const SizedBox(width: KkSpacing.md),
            const Text('传文件', style: KkType.h3),
          ],
        ),
        const SizedBox(height: KkSpacing.lg),
        // Phase 2 简化:用 URL 输入代替真文件选择(真文件上传 Phase 5 接 OSS)
        // 真文件选择器在移动端需 image_picker / file_picker,这里先用 URL
        TextField(
          controller: urlCtrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '文件下载链接 (https://…)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: KkSpacing.sm),
        TextField(
          controller: labelCtrl,
          decoration: const InputDecoration(
            hintText: '对象名(可选,如 脚本文件 / 压缩包)',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: KkSpacing.lg),
        _confirmButton(
          label: '加为「下载」',
          onTap: () {
            final url = urlCtrl.text.trim();
            if (url.isEmpty) return;
            widget.onAdded(TakeAction(
              source: url,
              takeKind: 'download',
              label: labelCtrl.text.trim().isEmpty
                  ? null
                  : labelCtrl.text.trim(),
            ));
            Navigator.pop(context);
          },
        ),
      ],
    );
  }

  // ── 放链接 ──
  Widget _linkForm() {
    final ctrl = TextEditingController();
    String detectedLabel = '';
    return StatefulBuilder(
      builder: (context, setState) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Tappable(
                  onTap: _backToMenu,
                  child: const Icon(Icons.arrow_back,
                      color: KkColors.t1, size: 22),
                ),
                const SizedBox(width: KkSpacing.md),
                const Text('放链接', style: KkType.h3),
              ],
            ),
            const SizedBox(height: KkSpacing.lg),
            TextField(
              controller: ctrl,
              autofocus: true,
              onChanged: (v) {
                setState(() {
                  final (label, _) = detectLinkLabel(v);
                  detectedLabel = label;
                });
              },
              decoration: const InputDecoration(
                hintText: 'https://…',
                border: OutlineInputBorder(),
              ),
            ),
            // 当场识别(HANDOFF §4 验收:放 GitHub 链接 → 当场识别并标出)
            if (detectedLabel.isNotEmpty) ...[
              const SizedBox(height: KkSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: KkSpacing.md,
                  vertical: KkSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: KkColors.mint,
                  borderRadius: BorderRadius.circular(KkRadius.sm),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outline,
                        size: 14, color: KkColors.teal),
                    const SizedBox(width: KkSpacing.xs),
                    Text(
                      '将显示为「$detectedLabel」',
                      style: KkType.bodySm.copyWith(color: KkColors.teal),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: KkSpacing.lg),
            _confirmButton(
              label: '加为「跳转」',
              onTap: () {
                final url = ctrl.text.trim();
                if (url.isEmpty || !isValidUrl(url)) return;
                final (label, _) = detectLinkLabel(url);
                widget.onAdded(GoAction(
                  url: url,
                  label: label.isEmpty ? null : label,
                ));
                Navigator.pop(context);
              },
            ),
          ],
        );
      },
    );
  }

  Widget _confirmButton({required String label, required VoidCallback onTap}) {
    return Tappable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(KkRadius.md),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: KkSpacing.md),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: KkColors.teal,
          borderRadius: BorderRadius.circular(KkRadius.md),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontFamily: 'JetBrainsMono',
          ),
        ),
      ),
    );
  }
}

enum _Mode { menu, text, file, link }
