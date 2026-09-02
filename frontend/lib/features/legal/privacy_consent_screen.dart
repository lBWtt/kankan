import 'package:flutter/material.dart';

import '../../core/theme/kk_colors.dart';
import '../../core/theme/tokens.dart';
import 'legal_docs.dart';

/// 首次运行隐私选择页。
///
/// 在用户作出选择前不挂载业务路由，因此不会提前拉取内容、恢复账号或发送埋点。
/// 拒绝匿名改进数据仍可进入游客浏览；需要手机号的功能在登录时另行明确征得同意。
class PrivacyConsentScreen extends StatelessWidget {
  final Future<void> Function(bool allowAnonymousAnalytics) onDecision;

  const PrivacyConsentScreen({super.key, required this.onDecision});

  Future<void> _showDocument(
    BuildContext context, {
    required String title,
    required String body,
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: SelectableText(body, style: KkType.bodySm),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KkColors.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(KkSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: KkColors.bgCard,
                  borderRadius: BorderRadius.circular(KkRadius.xl),
                  border: Border.all(color: KkColors.bd),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(KkSpacing.xl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('欢迎使用看看', style: KkType.h1),
                      const SizedBox(height: KkSpacing.sm),
                      Text(
                        '请选择数据使用范围。无论是否允许匿名改进数据，你都可以浏览公开作品。',
                        style: KkType.body.copyWith(color: KkColors.t2),
                      ),
                      const SizedBox(height: KkSpacing.lg),
                      const _ConsentItem(
                        title: '提供服务所必需',
                        body: '联网读取公开内容、保存本机设置；登录时才处理你主动提交的手机号和账号内容。',
                      ),
                      const SizedBox(height: KkSpacing.md),
                      const _ConsentItem(
                        title: '可选的匿名改进数据',
                        body: '记录页面访问、作品点击等匿名事件，用于判断产品是否有用；不出售个人信息。',
                      ),
                      const SizedBox(height: KkSpacing.md),
                      Wrap(
                        spacing: KkSpacing.md,
                        children: [
                          TextButton(
                            onPressed: () => _showDocument(
                              context,
                              title: kPrivacyPolicyTitle,
                              body: kPrivacyPolicy,
                            ),
                            child: const Text('阅读隐私政策'),
                          ),
                          TextButton(
                            onPressed: () => _showDocument(
                              context,
                              title: kUserAgreementTitle,
                              body: kUserAgreement,
                            ),
                            child: const Text('阅读用户协议'),
                          ),
                        ],
                      ),
                      const SizedBox(height: KkSpacing.md),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () => onDecision(true),
                          style: FilledButton.styleFrom(
                            backgroundColor: KkColors.teal,
                            minimumSize: const Size.fromHeight(48),
                          ),
                          child: const Text('同意并继续'),
                        ),
                      ),
                      const SizedBox(height: KkSpacing.sm),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: () => onDecision(false),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                          ),
                          child: const Text('拒绝匿名改进数据并继续'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ConsentItem extends StatelessWidget {
  final String title;
  final String body;

  const _ConsentItem({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: Icon(Icons.check_circle_outline, color: KkColors.teal),
        ),
        const SizedBox(width: KkSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: KkType.body.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(body, style: KkType.bodySm.copyWith(color: KkColors.t3)),
            ],
          ),
        ),
      ],
    );
  }
}
