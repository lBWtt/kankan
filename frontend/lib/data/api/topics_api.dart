// 这个文件是干什么的：封装话题接口（热门话题列表 + 话题详情）+ 把后端 TopicOut/TopicDetail 映射成前端模型。
// 它对应产品里的什么功能：话题广场、今日话题横条（列表）、话题详情页（某 #tag 下的项目+动态）。
// 如果它出错了：话题广场/话题页在真数据模式下拉不到内容。
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/app_exception.dart';
import '../../core/network/dio_provider.dart';
import '../../domain/models/models.dart';
import 'posts_api.dart' show postFromJson;
import '../dto/project_card_dto.dart' show projectFromCardJson;

/// 话题详情一次拉取：热度头 + 该 tag 下项目 + 动态（+ 我已赞的动态 id）。
class TopicBundle {
  final Topic topic;
  final List<Project> projects;
  final List<Post> posts;
  final Set<String> likedIds;
  final bool isFollowed;
  const TopicBundle(this.topic, this.projects, this.posts, this.likedIds,
      {this.isFollowed = false});
}

Topic _topicFromJson(Map<String, dynamic> j) => Topic(
      tag: (j['tag'] ?? '').toString(),
      heat: _int(j['heat']),
      projectCount: _int(j['project_count']),
      postCount: _int(j['post_count']),
      totalLikes: _int(j['total_likes']),
    );

int _int(dynamic v) => v is int ? v : int.tryParse('$v') ?? 0;

class TopicsApi {
  final Dio _dio;
  TopicsApi(this._dio);

  /// GET /topics?limit= → 热门话题（按 heat 降序）。
  Future<List<Topic>> topTopics({int limit = 30}) async {
    try {
      final resp = await _dio.get<dynamic>(
        '/topics',
        queryParameters: {'limit': limit},
      );
      final data = resp.data;
      if (data is! List) return const [];
      return data
          .whereType<Map<dynamic, dynamic>>()
          .map((m) => _topicFromJson(Map<String, dynamic>.from(m)))
          .toList();
    } on DioException catch (e) {
      throw AppException.fromDio(e);
    }
  }

  Future<List<Topic>> followedTopics() async {
    try {
      final resp = await _dio.get<dynamic>('/topics/followed');
      final data = resp.data;
      if (data is! List) return const [];
      return data
          .whereType<Map<dynamic, dynamic>>()
          .map((m) => _topicFromJson(Map<String, dynamic>.from(m)))
          .toList();
    } on DioException catch (e) {
      throw AppException.fromDio(e);
    }
  }

  Future<void> setFollowed(String tag, bool followed) async {
    try {
      final path = '/topics/${Uri.encodeComponent(tag)}/follow';
      if (followed) {
        await _dio.post<dynamic>(path);
      } else {
        await _dio.delete<dynamic>(path);
      }
    } on DioException catch (e) {
      throw AppException.fromDio(e);
    }
  }

  /// GET /topics/{tag} → 话题详情（热度头 + 项目卡片 + 动态）。
  Future<TopicBundle> detail(String tag) async {
    try {
      final resp = await _dio.get<dynamic>('/topics/${Uri.encodeComponent(tag)}');
      final data = resp.data;
      if (data is! Map) {
        return TopicBundle(Topic(tag: tag), const [], const [], <String>{});
      }
      final m = Map<String, dynamic>.from(data);
      final topic = m['topic'] is Map
          ? _topicFromJson(Map<String, dynamic>.from(m['topic'] as Map))
          : Topic(tag: tag);
      final projects = (m['projects'] is List)
          ? (m['projects'] as List)
              .whereType<Map<dynamic, dynamic>>()
              .map((e) => projectFromCardJson(Map<String, dynamic>.from(e)))
              .toList()
          : <Project>[];
      final liked = <String>{};
      final posts = (m['posts'] is List)
          ? (m['posts'] as List)
              .whereType<Map<dynamic, dynamic>>()
              .map((e) => postFromJson(Map<String, dynamic>.from(e), liked))
              .toList()
          : <Post>[];
      return TopicBundle(topic, projects, posts, liked,
          isFollowed: (m['topic'] is Map) &&
              Map<String, dynamic>.from(m['topic'] as Map)['is_followed'] == true);
    } on DioException catch (e) {
      throw AppException.fromDio(e);
    }
  }
}

final topicsApiProvider = Provider<TopicsApi>((ref) => TopicsApi(ref.watch(dioProvider)));
