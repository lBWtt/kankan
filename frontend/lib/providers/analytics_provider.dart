// 这个文件是干什么的：埋点服务——攒事件成批发 POST /events（省流量），会话内曝光去重。
// 它对应产品里的什么功能：dashboard 漏斗（card_impression→detail_view→how_to_interest）+ hot_score。
// 如果它出错了：用户无感（best-effort）；漏斗少了这条流。
//
// 只对真后端项目（UUID）发 project_id——mock 项目（短 id）后端 project_id 要 UUID，发了 422，跳过。
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/prefs.dart';
import '../core/utils/backend_id.dart';
import '../data/api/events_api.dart';

class Analytics {
  final Ref _ref;
  final List<Map<String, dynamic>> _buffer = [];
  final Set<String> _impressed = {}; // 会话内曝光去重（同项目只记一次 card_impression）
  Timer? _timer;

  Analytics(this._ref) {
    // 定时冲刷：攒着的事件每 8 秒发一批（也在满 20 条时立即发）。
    _timer = Timer.periodic(const Duration(seconds: 8), (_) => flush());
    // provider 销毁时停定时器 + 最后冲刷一次（别丢尾巴上的事件）。
    _ref.onDispose(() {
      _timer?.cancel();
      flush();
    });
  }

  /// 记一条事件。projectId 为 mock 短 id 时整条跳过（后端 project_id 需 UUID）。
  void track(String eventName, {String? projectId, Map<String, dynamic>? payload}) {
    if (projectId != null && !looksLikeBackendId(projectId)) return;
    final e = <String, dynamic>{
      'event_name': eventName,
      'occurred_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (projectId != null) e['project_id'] = projectId;
    if (payload != null) e['payload'] = payload;
    _buffer.add(e);
    if (_buffer.length >= 20) flush();
  }

  /// 卡片曝光（会话内同项目只记一次，避免滚动 rebuild 重复计）。
  void trackImpressionOnce(String projectId) {
    if (!looksLikeBackendId(projectId)) return;
    if (!_impressed.add(projectId)) return;
    track('card_impression', projectId: projectId);
  }

  /// 冲刷缓冲：一次最多 50 条（后端上限），best-effort。
  Future<void> flush() async {
    if (_buffer.isEmpty) return;
    final n = _buffer.length > 50 ? 50 : _buffer.length;
    final batch = List<Map<String, dynamic>>.from(_buffer.take(n));
    _buffer.removeRange(0, n);
    await _ref.read(eventsApiProvider).sendBatch(
          batch,
          anonClientId: _ref.read(anonClientIdProvider),
        );
  }
}

final analyticsProvider = Provider<Analytics>((ref) => Analytics(ref));
