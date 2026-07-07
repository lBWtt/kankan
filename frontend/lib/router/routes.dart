/// 路由路径常量。
class KkRoutes {
  KkRoutes._();

  // ── Tab 路由(4 branches)──
  static const discover = '/discover';
  static const kankan = '/kankan';
  static const library = '/library';
  static const me = '/me';

  // ── 顶层路由(push,不进 shell)──
  /// 项目详情 — HANDOFF §6.7 真路由 + 深链(复制链接才有意义)
  static String detail(String id) => '/detail/$id';
  static const detailPattern = '/detail/:id';

  /// 项目发布 — HANDOFF §4
  static const publish = '/publish';

  /// 发动态 — 任务⑪:compose 屏(轻内容,对应 Post)
  static const compose = '/compose';

  // ── P0:实现线索(主信号下游,深链可直达)──
  /// 实现线索页 — 详情页「想看怎么做」入口(ZAI_PLAYBOOK P0)。
  /// 告诉用户作品怎么做出来的:来源 / 工具 / AI 思路 / 相关作品 / 订阅。
  static String clue(String id) => '/clue/$id';
  static const cluePattern = '/clue/:projectId';

  // ── Phase 3 激活的路由 ──

  /// 搜索页(输入 + 最近搜索,无 query 时展示热门话题)
  static const search = '/search';

  /// 搜索结果页(4 Tab:项目/动态/用户/话题)
  /// query 作为 path 参数(可深链 + 浏览器/系统返回栈正确)
  static String searchResults(String query) =>
      '/search/results/${Uri.encodeComponent(query)}';
  static const searchResultsPattern = '/search/results/:query';

  /// 个人主页 — HANDOFF §6.5 真路由(可深链)
  /// 看作品集 / 关注 / 收藏
  static String profile(String userId) => '/u/$userId';
  static const profilePattern = '/u/:userId';

  /// 通知中心 — HANDOFF §6.8
  static const notifications = '/notifications';

  // ── Phase 3 Tier 2 激活的路由(互动闭环)──

  /// 全屏评论 — HANDOFF §6.1 CommentThread 的全屏壳
  /// type ∈ {'project','post'}, id = hostId
  static String comments(String type, String id) =>
      '/comments/$type/$id';
  static const commentsPattern = '/comments/:type/:id';

  /// 动态详情 — HANDOFF §1 轻量详情(发现 feed 点击目标)
  static String postDetail(String id) => '/post/$id';
  static const postDetailPattern = '/post/:id';

  /// 关注/粉丝列表 — profile 屏关注/粉丝计数入口
  /// query: ?type=followers|following(默认 following)
  static String follows(String userId) => '/u/$userId/follows';
  static const followsPattern = '/u/:userId/follows';

  /// 资料编辑 — 编辑 'me'
  static const profileEdit = '/profile/edit';

  // ── Phase 3 Tier 3 激活的路由(进阶展示)──

  /// 榜单页 — kankan 屏榜单图标入口
  /// 三 Tab:项目榜 / 动态榜 / 作者榜,领奖台 + 名次升降
  static const ranking = '/ranking';

  /// 话题页 — 独立路由(可深链,搜索结果/话题列表点入)
  /// Posts/Projects 双 Tab,真实 heat(HANDOFF §6.10 禁 ×8+30 编造)
  static String topic(String tag) => '/topic/${Uri.encodeComponent(tag)}';
  static const topicPattern = '/topic/:tag';

  /// 话题广场 — 任务⑬:热门话题榜(全话题按 heat 降序)。
  /// 发现页「今日话题 → 话题广场」入口,整行点 → topic(tag)。
  static const topicPlaza = '/topics';

  /// 个人活动页 — me 屏热力图卡入口
  /// 大热力图 + 真实获收藏数 + 时间线
  static const activity = '/activity';

  /// 设置页 — me 屏设置图标入口
  /// 通知 / 外观 / 主题 / 清缓存(显示真实字节数)
  static const settings = '/settings';

  /// 登录 / 注册 — 手机号或邮箱验证码登录（未注册自动注册）。
  /// 「我的」页点头像/「点击登录」或设置页「账号」区进入；拿真 JWT 解锁写操作。
  static const login = '/login';
}
