import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/seed/mock_seed.dart';
import '../../domain/models/models.dart';

/// P1:Repo-module-private backing list — 启动期从 mockProjects 拷贝一次,
/// 此后 repo 运行时读写都走它,不再 reach into mock_seed 全局。
///
/// 为什么是 top-level final 而非在 provider create 里 `List.of(mockProjects)`:
/// publish 屏 `add()` 后会 `ref.invalidate(projectRepositoryProvider)`(强制
/// watch 重建)。若每次 create 都新拷一份,新发布的项目会在 invalidate 时丢失
/// (新副本取自未被改写的全局)。top-level final 只在首次访问时拷一次,后续
/// invalidate 传同一个引用,`add()` 的改动跨 invalidate 存活——行为不变。
///
/// 与 SearchRepository 共享(同源):发布的新项目要能被搜到,search 必须读同一份。
/// mockUsers / mockComments 保留全局引用——updateProfile 写 mockUsers、screens
/// 直接调 mock_seed.commentsFor(hostId) 读 mockComments,改 owned 副本会撕裂读写。
final List<Project> backingProjects = List.of(mockProjects);

/// HANDOFF §8.1:Drift 推迟。Phase 2 用内存 repository,Phase 5 真有复杂缓存再上。
///
/// 这是 ProjectRepository — 持有 owned 数据副本(P1 解耦)。构造期由 provider
/// 注入 [backingProjects](从 mock_seed 一次拷贝),运行时 all/byId/sorted/add 等
/// 全部读写 owned 副本,不再 reach into 全局。Phase 5 替换为 Drift/Hive 后端时
/// 只改此文件,上层 provider/feature 不动(依赖倒置)。
class ProjectRepository {
  final List<Project> _projects;
  final List<KkUser> _users;
  // F-4:与 PostRepository 同源(mockComments 共享引用),
  // addComment 写入此列表,detail 底栏 / 卡片 / CommentThread 读同一份。
  // P1:mockComments 保留全局引用(见 backingProjects 注释),owned 副本会撕裂
  // screens 直接调的 mock_seed.commentsFor。
  final List<Comment> _comments;

  ProjectRepository(this._projects, this._users, this._comments);

  /// 按 ID 取项目
  Project? byId(String id) =>
      _projects.where((p) => p.id == id).firstOrNull;

  /// 全部项目(按 domain 筛选,可选)
  ///
  /// F-36:返回可变副本 `List.of(_projects)`,不再用 `List.unmodifiable` /
  /// `toList(growable: false)`。原因:不可变 List 调 `..sort()` 会运行时抛
  /// `UnsupportedError`(discover 屏踩过)。调用方若需排序可直接 sort,无需
  /// 先 toList。若需防止外部修改,调用方自行 `.toList()` 复制。
  /// 约定(Codex 规则 C):repository 的 all() 统一返回可变副本,所有调用方
  /// 可直接 sort,不必每次 toList —— 二选一,这里选"可变副本"。
  List<Project> all({String? domain}) {
    if (domain == null) return List.of(_projects);
    return _projects.where((p) => p.domain == domain).toList();
  }

  /// 三 Tab 真排序(HANDOFF §6.9 + Web 版 kankan 屏规范)
  ///   - sort == 'hot'  → 按 likes 降序
  ///   - sort == 'new'  → 按 createdAtMs 降序
  ///   - sort == 'featured' → 默认顺序(mock seed 顺序即精选)
  List<Project> sorted(String sort, {String? domain}) {
    final list = all(domain: domain).toList();
    switch (sort) {
      case 'hot':
        list.sort((a, b) => b.likes.compareTo(a.likes));
      case 'new':
        list.sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
      case 'featured':
      default:
        break; // 保持 seed 顺序
    }
    return list;
  }

  /// 按标签找(HANDOFF §6.2 — 真实 tags 索引,Web 版靠标题子串硬凑的罪)
  List<Project> byTag(String tag) =>
      _projects.where((p) => p.tags.contains(tag)).toList();

  /// 用户发的项目
  List<Project> byAuthor(String userId) =>
      _projects.where((p) => p.authorId == userId).toList();

  /// 作者查找
  KkUser? userById(String id) =>
      _users.where((u) => u.id == id).firstOrNull;

  /// take 成功后 +1(HANDOFF §2.2)
  /// Phase 2 简化:仅内存更新;Phase 5 接 Drift 持久化。
  void incrementTakeaway(String projectId) {
    final p = byId(projectId);
    if (p != null) {
      _projects[_projects.indexOf(p)] = p.copyWith(
        takeawayCount: p.takeawayCount + 1,
      );
    }
  }

  /// F-2:发布的项目写入 owned _projects 列表头部(P1:即 backingProjects,
  /// 不再写 mockProjects 全局)。发布后 discover / kankan / profile 重新读取即可见。
  /// 内存级即可,不碰 Drift(Phase 5 接后端时替换)。
  void add(Project project) {
    _projects.insert(0, project);
  }

  /// 删除自己发布的项目(对称 add)。详情页/我的页 own 二次确认后调用,
  /// 写 owned _projects(backingProjects)。真·后端 DELETE /projects/{id} 由
  /// Claude 后续接,这里先 mock 层(内存 repo 删除)。
  void removeProject(String projectId) {
    _projects.removeWhere((p) => p.id == projectId);
  }

  /// F-4:写入评论到 _comments(P1:仍是 mockComments 全局引用——screens 直接
  /// 调 mock_seed.commentsFor 读它,改 owned 副本会撕裂读写)。与 PostRepository
  /// 同源,detail 底栏 / 卡片 / CommentThread 读同一份,计数一致。
  /// hostType/hostId 透传仅作文档;Comment 自身已带这两个字段。
  void addComment(String hostType, String hostId, Comment comment) {
    _comments.add(comment);
  }

  /// 任务⑨:删除评论(对称 addComment)。CommentThread 长按删除二次确认后调用,
  /// 同步 _comments(mockComments),杜绝 detail 底栏「心得 N」从 commentsFor
  /// 重读时计数分裂。楼中楼回复是 Comment 内嵌 replies,不单独入 _comments,
  /// 删除顶级评论时其 replies 随之消失(本地 state 已 removeWhere 整条)。
  void removeComment(String commentId) {
    _comments.removeWhere((c) => c.id == commentId);
  }

  /// 任务⑨:更新评论(编辑)。CommentThread _editingId 提交时调用,
  /// 同步 _comments(mockComments)中对应记录,content 替换,其余字段不变。
  void updateComment(Comment updated) {
    final i = _comments.indexWhere((c) => c.id == updated.id);
    if (i >= 0) _comments[i] = updated;
  }
}

/// Repository provider(单例,全局共享)。
/// P1:注入 [backingProjects](owned 副本,跨 invalidate 存活)。mockUsers / mockComments
/// 保留全局引用(updateProfile / commentsFor 依赖,见类注释)。
/// Phase 5 替换为 Drift 时,改此 provider 即可。
final projectRepositoryProvider = Provider<ProjectRepository>((ref) {
  return ProjectRepository(backingProjects, mockUsers, mockComments);
});
