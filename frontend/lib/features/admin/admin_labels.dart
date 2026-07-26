// 审核页共用的中文标签映射 + 风控标 chip（枚举值 → 人话）。
import 'package:flutter/material.dart';

import '../../core/theme/kk_colors.dart';
import '../../core/theme/tokens.dart';

const _riskLabels = {
  'suspected_ad': '疑似广告',
  'duplicate': '疑似重复',
  'copyright_risk': '疑似侵权',
  'low_quality': '低质',
};

String riskLabel(String flag) => _riskLabels[flag] ?? flag;

const _platformLabels = {
  'xiaohongshu': '小红书',
  'douyin': '抖音',
  'kuaishou': '快手',
  'bilibili': 'B站',
  'weibo': '微博',
  'zhihu': '知乎',
  'github': 'GitHub',
  'jike': '即刻',
};

String platformLabel(String p) => _platformLabels[p] ?? p;

/// 五维分维度中文名（scores_json 的 key）。
const scoreDimLabels = {
  'fun': '趣味',
  'shareable': '可分享',
  'fresh': '新鲜',
  'useful': '实用',
  'reproducible': '可复刻',
};

/// 风控标 chip：珊瑚橙描边（警示但不刺眼）。
class RiskChip extends StatelessWidget {
  final String flag;
  const RiskChip({super.key, required this.flag});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: KkColors.coralMint,
        borderRadius: BorderRadius.circular(KkRadius.sm),
        border: Border.all(color: const Color(0x59D85A30)), // 珊瑚橙 35%
      ),
      child: Text(
        riskLabel(flag),
        style: KkType.mono.copyWith(
            color: KkColors.coralDark,
            fontSize: 11,
            fontWeight: FontWeight.w600),
      ),
    );
  }
}
