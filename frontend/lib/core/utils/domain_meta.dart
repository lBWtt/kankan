// 这个文件是干什么的：领域(content_type)的「中文标签 + 图标」唯一来源。
// 为什么存在：之前 _domainLabel / _domainIcon 在 post_card / detail / me 等好几处各写一遍，
//   改一个领域名要改好几处、必漏一处（"改了又出现"的结构性根因）。收进这一处，改一次全站生效。
import 'package:flutter/material.dart';

/// 7 领域值 → 中文标签（与 profile_edit 的领域选项同源）。未知值原样返回。
const Map<String, String> kDomainLabels = <String, String>{
  'ai_image': 'AI 图像',
  'ai_video': 'AI 视频',
  'web': '网站',
  'app': '应用',
  'tool': '效率工具',
  'opensource': '开源项目',
  'prompt': '提示词',
};

String domainLabel(String value) => kDomainLabels[value] ?? value;

const Map<String, String> kDomainGroups = <String, String>{
  'ai_image': '创作',
  'ai_video': '创作',
  'web': '产品',
  'app': '产品',
  'opensource': '开发',
  'tool': '效率',
  'prompt': '效率',
};

String domainGroup(String value) => kDomainGroups[value] ?? '其他';

const List<({String title, List<String> values})> kDomainGroupOptions = [
  (title: '创作', values: ['ai_image', 'ai_video']),
  (title: '产品', values: ['web', 'app']),
  (title: '开发', values: ['opensource']),
  (title: '效率', values: ['tool', 'prompt']),
];

/// 领域 → 图标（引用卡小封面 / 徽标用）。
IconData domainIcon(String domain) {
  switch (domain) {
    case 'ai_image':
      return Icons.image_outlined;
    case 'ai_video':
      return Icons.play_circle_outline;
    case 'web':
      return Icons.language;
    case 'app':
      return Icons.phone_iphone;
    case 'tool':
      return Icons.build_outlined;
    case 'opensource':
      return Icons.code;
    case 'prompt':
      return Icons.chat_bubble_outline;
    default:
      return Icons.article_outlined;
  }
}
