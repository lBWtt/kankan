import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/widgets/kk_tab_bar.dart';
import '../features/activity/activity_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/comments/comments_screen.dart';
import '../features/clue/implementation_clue_screen.dart';
import '../features/detail/detail_screen.dart';
import '../features/discover/discover_screen.dart';
import '../features/follows/follows_screen.dart';
import '../features/kankan/kankan_screen.dart';
import '../features/library/library_screen.dart';
import '../features/me/me_screen.dart';
import '../features/notifications/notifications_screen.dart';
import '../features/post_detail/post_detail_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/profile_edit/profile_edit_screen.dart';
import '../features/publish/compose_screen.dart';
import '../features/publish/publish_entry_sheet.dart';
import '../features/publish/publish_screen.dart';
import '../features/ranking/ranking_screen.dart';
import '../features/search/search_results_screen.dart';
import '../features/search/search_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/topic/topic_plaza_screen.dart';
import '../features/topic/topic_screen.dart';
import 'routes.dart';

/// 全局 GoRouter provider。
///
/// Phase 4:Hero 共享元素需在 app.dart 的 MaterialApp.router 配置
/// `heroControllerCreator: () => const MaterialHeroController()`,本 router 已
/// 支持 Hero tag 传递(顶层过渡页用 CustomTransitionPage 不影响 Hero,
/// Hero 由 child 内部的 Hero widget 自带,GoRouter 会透传到 Navigator)。
///
/// 5 槽视觉 = 4 branch(发现/看看/收藏/我的)+ 中间 FAB(弹 sheet)。
/// 顶层路由(push,不进 shell,全屏沉浸,统一 300ms 淡入 + 轻微上滑过渡):
///   - /detail/:id           项目详情
///   - /publish              发布
///   - /search               搜索(输入 + 最近搜索)
///   - /search/results/:q    搜索结果(4 Tab)
///   - /u/:userId            个人主页
///   - /notifications        通知中心
final goRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: KkRoutes.discover,
    debugLogDiagnostics: true,
    routes: [
      // ── 顶层路由:详情(深链,HANDOFF §6.7)──
      GoRoute(
        path: KkRoutes.detailPattern,
        pageBuilder: (context, state) => _kkPage(
          context: context,
          state: state,
          child: DetailScreen(
            projectId: state.pathParameters['id']!,
          ),
        ),
      ),

      // ── 顶层路由:发布(HANDOFF §4)──
      GoRoute(
        path: KkRoutes.publish,
        pageBuilder: (context, state) => _kkPage(
          context: context,
          state: state,
          child: const PublishScreen(),
        ),
      ),

      // ── 顶层路由:发动态(任务⑪ compose 屏,对应 Post)──
      GoRoute(
        path: KkRoutes.compose,
        pageBuilder: (context, state) => _kkPage(
          context: context,
          state: state,
          child: const ComposeScreen(),
        ),
      ),

      // ── P0:实现线索(详情页「想看怎么做」入口,深链可直达)──
      GoRoute(
        path: KkRoutes.cluePattern,
        pageBuilder: (context, state) => _kkPage(
          context: context,
          state: state,
          child: ImplementationClueScreen(
            projectId: state.pathParameters['projectId']!,
          ),
        ),
      ),

      // ── Phase 3:搜索 ──
      GoRoute(
        path: KkRoutes.search,
        pageBuilder: (context, state) => _kkPage(
          context: context,
          state: state,
          child: const SearchScreen(),
        ),
      ),
      GoRoute(
        path: KkRoutes.searchResultsPattern,
        pageBuilder: (context, state) => _kkPage(
          context: context,
          state: state,
          child: SearchResultsScreen(
            query: Uri.decodeComponent(state.pathParameters['query']!),
          ),
        ),
      ),

      // ── Phase 3:个人主页(HANDOFF §6.5 真路由)──
      GoRoute(
        path: KkRoutes.profilePattern,
        pageBuilder: (context, state) => _kkPage(
          context: context,
          state: state,
          child: ProfileScreen(
            userId: state.pathParameters['userId']!,
          ),
        ),
      ),

      // ── Phase 3:通知中心(HANDOFF §6.8)──
      GoRoute(
        path: KkRoutes.notifications,
        pageBuilder: (context, state) => _kkPage(
          context: context,
          state: state,
          child: const NotificationsScreen(),
        ),
      ),

      // ── Phase 3 Tier 2:互动闭环 ──

      // 全屏评论(HANDOFF §6.1 CommentThread 全屏壳)
      GoRoute(
        path: KkRoutes.commentsPattern,
        pageBuilder: (context, state) => _kkPage(
          context: context,
          state: state,
          child: CommentsScreen(
            hostType: state.pathParameters['type']!,
            hostId: state.pathParameters['id']!,
          ),
        ),
      ),

      // 动态详情(HANDOFF §1 轻量详情,发现 feed 点击目标)
      GoRoute(
        path: KkRoutes.postDetailPattern,
        pageBuilder: (context, state) => _kkPage(
          context: context,
          state: state,
          child: PostDetailScreen(
            postId: state.pathParameters['id']!,
          ),
        ),
      ),

      // 关注/粉丝列表(profile 屏入口)
      GoRoute(
        path: KkRoutes.followsPattern,
        pageBuilder: (context, state) => _kkPage(
          context: context,
          state: state,
          child: FollowsScreen(
            userId: state.pathParameters['userId']!,
            initialTab: state.uri.queryParameters['type'] ?? 'following',
          ),
        ),
      ),

      // 资料编辑(编辑 'me')
      GoRoute(
        path: KkRoutes.profileEdit,
        pageBuilder: (context, state) => _kkPage(
          context: context,
          state: state,
          child: const ProfileEditScreen(),
        ),
      ),

      // ── Phase 3 Tier 3:进阶展示 ──

      // 榜单(kankan 屏榜单图标入口)
      GoRoute(
        path: KkRoutes.ranking,
        pageBuilder: (context, state) => _kkPage(
          context: context,
          state: state,
          child: const RankingScreen(),
        ),
      ),

      // 话题页(独立路由,可深链)
      GoRoute(
        path: KkRoutes.topicPattern,
        pageBuilder: (context, state) => _kkPage(
          context: context,
          state: state,
          child: TopicScreen(
            tag: Uri.decodeComponent(state.pathParameters['tag']!),
          ),
        ),
      ),

      // 话题广场(任务⑬:热门话题榜,发现页今日话题入口)
      GoRoute(
        path: KkRoutes.topicPlaza,
        pageBuilder: (context, state) => _kkPage(
          context: context,
          state: state,
          child: const TopicPlazaScreen(),
        ),
      ),

      // 个人活动(me 屏热力图卡入口)
      GoRoute(
        path: KkRoutes.activity,
        pageBuilder: (context, state) => _kkPage(
          context: context,
          state: state,
          child: const ActivityScreen(),
        ),
      ),

      // 设置(me 屏设置图标入口)
      GoRoute(
        path: KkRoutes.settings,
        pageBuilder: (context, state) => _kkPage(
          context: context,
          state: state,
          child: const SettingsScreen(),
        ),
      ),

      // 登录 / 注册(拿真 JWT 解锁写操作;设置「账号」区 / 「我的」页入口)
      GoRoute(
        path: KkRoutes.login,
        pageBuilder: (context, state) => _kkPage(
          context: context,
          state: state,
          child: const LoginScreen(),
        ),
      ),

      // ── Tab shell(4 branches + FAB)──
      // 不加过渡动画:StatefulShellRoute.indexedStack 靠 builder 保活,
      // 改过渡方式会破坏 indexedStack 的保活机制(HANDOFF §5)。
      // Tab 切换是底栏 selectedIndex 改变,不走 Navigator push/pop,本就无过渡。
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return KkRootShell(
            navigationShell: navigationShell,
            onPublishTap: () => _showPublishEntrySheet(context),
          );
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: KkRoutes.discover,
                builder: (context, state) => const DiscoverScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: KkRoutes.kankan,
                builder: (context, state) => const KankanScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: KkRoutes.library,
                builder: (context, state) => const LibraryScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: KkRoutes.me,
                builder: (context, state) => const MeScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

/// Phase 4-a:顶层路由通用过渡页工厂。
///
/// 过渡组合(同步驱动同一 `animation`,300ms 内完成):
///   - fade:Tween<double>(0 → 1),曲线 Curves.easeOut
///   - slide:Tween<Offset>((0, 0.04) → (0, 0)),曲线 Curves.easeOutCubic
///     上滑幅度 4% 屏高,克制不抢戏(参考 iOS push / Material fade-through)
///
/// 时长 300ms(与 Phase 3 Tier 4 骨架屏 placeholder 时长一致,体感统一)。
///
/// 不破坏深链(HANDOFF §6.7):工厂内仍读 state.pathParameters /
/// state.uri.queryParameters,深链 URL 直达本路由会得到同样的过渡 + 同样的参数解析。
///
/// Hero 共享元素:工厂返回的 CustomTransitionPage 不影响 Hero,
/// child 内部的 Hero widget 会通过 Navigator 透传 tag,Phase 4 后续在 app.dart
/// 配置 heroControllerCreator 即可启用。
///
/// key:state.pageKey 让 GoRouter 识别本页路由身份,支持 go/pop 状态恢复。
CustomTransitionPage<void> _kkPage({
  required BuildContext context,
  required GoRouterState state,
  required Widget child,
}) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 300),
    reverseTransitionDuration: const Duration(milliseconds: 300),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final fade = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOut,
      ).drive(Tween<double>(begin: 0, end: 1));
      final slide = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      ).drive(
        Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero),
      );
      return FadeTransition(
        opacity: fade,
        child: SlideTransition(
          position: slide,
          child: child,
        ),
      );
    },
  );
}

/// 显示发布入口 sheet(二选一:发动态 / 发作品)。
/// 选"发作品" → push 到 /publish。
/// 选"发动态" → push 到 /compose(任务⑪)。
void _showPublishEntrySheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => PublishEntrySheet(
      onPublishProject: () {
        Navigator.pop(context);
        context.push(KkRoutes.publish);
      },
      onPublishPost: () {
        Navigator.pop(context);
        context.push(KkRoutes.compose);
      },
    ),
  );
}
