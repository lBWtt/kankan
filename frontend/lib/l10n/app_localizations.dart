import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh')
  ];

  /// App 名称(MaterialApp.title、顶栏标题)。
  ///
  /// In zh, this message translates to:
  /// **'看看'**
  String get appTitle;

  /// 底栏 Tab 1:发现页。
  ///
  /// In zh, this message translates to:
  /// **'发现'**
  String get discoverTab;

  /// 底栏 Tab 2:项目 feed。
  ///
  /// In zh, this message translates to:
  /// **'看看'**
  String get kankanTab;

  /// 底栏 Tab 3:内容库。
  ///
  /// In zh, this message translates to:
  /// **'收藏'**
  String get libraryTab;

  /// 底栏 Tab 4:个人页。
  ///
  /// In zh, this message translates to:
  /// **'我的'**
  String get meTab;

  /// 发布动作(FAB、发布入口 sheet 标题)。
  ///
  /// In zh, this message translates to:
  /// **'发布'**
  String get publish;

  /// 搜索动作(顶栏搜索图标 semanticLabel、搜索页标题)。
  ///
  /// In zh, this message translates to:
  /// **'搜索'**
  String get search;

  /// 收藏动作(项目卡收藏按钮 semanticLabel)。
  ///
  /// In zh, this message translates to:
  /// **'收藏'**
  String get save;

  /// 点赞动作(动态/项目卡点赞按钮 semanticLabel)。
  ///
  /// In zh, this message translates to:
  /// **'点赞'**
  String get like;

  /// 评论动作(动态/项目卡评论按钮 semanticLabel)。
  ///
  /// In zh, this message translates to:
  /// **'评论'**
  String get comment;

  /// 分享动作(详情页分享按钮 semanticLabel)。
  ///
  /// In zh, this message translates to:
  /// **'分享'**
  String get share;

  /// 关注作者按钮(未关注态)。
  ///
  /// In zh, this message translates to:
  /// **'关注'**
  String get follow;

  /// 关注作者按钮(已关注态)。
  ///
  /// In zh, this message translates to:
  /// **'已关注'**
  String get unfollow;

  /// 删除动作(拿走物长按菜单等)。
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get delete;

  /// 取消(sheet 末项、对话框)。
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get cancel;

  /// 确认对话框主按钮。
  ///
  /// In zh, this message translates to:
  /// **'确定'**
  String get confirm;

  /// 错误态重试按钮(RemoteError)。
  ///
  /// In zh, this message translates to:
  /// **'重试'**
  String get retry;

  /// 看看页顶栏榜单图标 semanticLabel。
  ///
  /// In zh, this message translates to:
  /// **'榜单'**
  String get ranking;

  /// feed 空状态(发现/看看)。
  ///
  /// In zh, this message translates to:
  /// **'这里还没有内容'**
  String get emptyFeed;

  /// 通用空状态(EmptyState generic variant)。
  ///
  /// In zh, this message translates to:
  /// **'什么都没找到'**
  String get emptyGeneric;

  /// 搜索结果空状态。
  ///
  /// In zh, this message translates to:
  /// **'搜不到相关内容'**
  String get emptySearch;

  /// 加载失败兜底文案。
  ///
  /// In zh, this message translates to:
  /// **'加载失败'**
  String get loadFailed;

  /// 远程数据加载失败文案(RemoteError message)。
  ///
  /// In zh, this message translates to:
  /// **'连不上服务器'**
  String get connectFailed;

  /// 项目卡整体无障碍标签(读屏念「项目:标题」)。占位符 {title} 替换为项目标题。
  ///
  /// In zh, this message translates to:
  /// **'项目:{title}'**
  String projectSemantic(Object title);

  /// 动态卡整体无障碍标签。占位符 {author} 替换为作者名。
  ///
  /// In zh, this message translates to:
  /// **'动态:{author}'**
  String postSemantic(Object author);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
