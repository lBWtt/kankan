// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => '看看';

  @override
  String get discoverTab => '发现';

  @override
  String get kankanTab => '看看';

  @override
  String get libraryTab => '收藏';

  @override
  String get meTab => '我的';

  @override
  String get publish => '发布';

  @override
  String get search => '搜索';

  @override
  String get save => '收藏';

  @override
  String get like => '点赞';

  @override
  String get comment => '评论';

  @override
  String get share => '分享';

  @override
  String get follow => '关注';

  @override
  String get unfollow => '已关注';

  @override
  String get delete => '删除';

  @override
  String get cancel => '取消';

  @override
  String get confirm => '确定';

  @override
  String get retry => '重试';

  @override
  String get ranking => '榜单';

  @override
  String get emptyFeed => '这里还没有内容';

  @override
  String get emptyGeneric => '什么都没找到';

  @override
  String get emptySearch => '搜不到相关内容';

  @override
  String get loadFailed => '加载失败';

  @override
  String get connectFailed => '连不上服务器';

  @override
  String projectSemantic(Object title) {
    return '项目:$title';
  }

  @override
  String postSemantic(Object author) {
    return '动态:$author';
  }
}
