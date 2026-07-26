import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/kk_colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/tappable.dart';
import '../../../domain/models/models.dart';

/// 成果区 repo 渲染器 — HANDOFF §2.1 GitHub 等仓库卡。
///
/// 显示:图标 + name + ★stars + 语言 + description。
/// 卡片整体可点 → go 到仓库 url(url_launcher 真开外链)。
class RepoCard extends StatelessWidget {
  final RepoInfo repo;

  const RepoCard({super.key, required this.repo});

  @override
  Widget build(BuildContext context) {
    return Tappable(
      onTap: () => _openUrl(repo.url),
      borderRadius: BorderRadius.circular(KkRadius.md),
      child: Container(
        padding: const EdgeInsets.all(KkSpacing.lg),
        decoration: BoxDecoration(
          color: KkColors.bgCard,
          borderRadius: BorderRadius.circular(KkRadius.md),
          border: Border.all(color: KkColors.bd),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 仓库图标
            const Icon(Icons.book_outlined, color: KkColors.teal, size: 22),
            const SizedBox(width: KkSpacing.md),
            // 主体
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // fullName(owner/repo)
                  Text(
                    repo.fullName,
                    style: KkType.mono.copyWith(color: KkColors.teal),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  // description
                  if (repo.description != null) ...[
                    Text(repo.description!, style: KkType.bodySm),
                    const SizedBox(height: KkSpacing.sm),
                  ],
                  // 语言（GitHub star 数在 App 里不刷新、恒为 0，按用户反馈直接不显示；只留语言）
                  if (repo.language.isNotEmpty)
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: KkColors.teal,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          repo.language,
                          style: KkType.mono.copyWith(fontSize: 12),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            // 行尾 ↗(go 表意)
            const Icon(Icons.open_in_new,
                size: 16, color: KkColors.t3),
          ],
        ),
      ),
    );
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
