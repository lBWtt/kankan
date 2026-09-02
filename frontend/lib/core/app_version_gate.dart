// 这个文件是干什么的：App 启动时的版本检查 / kill-switch 客户端。
// 它对应产品里的什么功能：侧载 APK 的远程版本管控——后端把某版标记 blocked / 抬高
//   最低支持版本时，那些用户启动被不可关弹窗拦住、只能去更新（配 backend/app_meta.py）。
// 如果它出错了：检查失败(网络等)一律放行——绝不能因为版本检查把用户挡在门外。
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'config/app_config.dart';

/// 启动版本闸。返回 true = 被强制拦截（调用方应停止后续引导，如 onboarding）。
/// web 恒为部署的最新版，跳过检查。
Future<bool> runAppVersionGate(BuildContext context) async {
  if (kIsWeb) return false;
  try {
    final info = await PackageInfo.fromPlatform();
    final build = int.tryParse(info.buildNumber) ?? 0;
    final platform =
        defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
    final res = await Dio().get(
      '${AppConfig.apiBaseUrl}/app/version-check',
      queryParameters: {'build': build, 'platform': platform},
      options: Options(
        receiveTimeout: const Duration(seconds: 6),
        sendTimeout: const Duration(seconds: 6),
      ),
    );
    final data = res.data;
    if (data is! Map) return false;
    final apkUrl = (data['apk_url'] ?? '').toString();
    final message = (data['message'] ?? '有新版本').toString();
    if (data['force_update'] == true) {
      if (context.mounted) await _showForce(context, message, apkUrl);
      return true;
    }
    if (data['update_available'] == true && context.mounted) {
      _showSoft(context, message, apkUrl);
    }
  } catch (_) {
    // 检查失败 → 放行。
  }
  return false;
}

Future<void> _openUpdate(String url) async {
  final uri = Uri.tryParse(url);
  if (uri != null) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// 强制更新：不可关弹窗（返回键也退不出），只能「去更新」。
Future<void> _showForce(BuildContext context, String message, String apkUrl) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('需要更新'),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => _openUpdate(apkUrl),
            child: const Text('去更新'),
          ),
        ],
      ),
    ),
  );
}

/// 软提示：可忽略的 SnackBar。
void _showSoft(BuildContext context, String message, String apkUrl) {
  try {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: '去更新',
          onPressed: () => _openUpdate(apkUrl),
        ),
      ),
    );
  } catch (_) {}
}
