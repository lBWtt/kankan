// 这个文件是干什么的：封装项目互动的写接口——收藏 / 取消收藏（真写后端）。
// 它对应产品里的什么功能：详情页/卡片的「收藏」按钮，登录后真落库。
// 如果它出错了：收藏点了不落库（调用方会回滚本地状态，保持与后端一致）。
//
// 只做收藏（favorite）：它与前端 savedProjectIds 是干净的 1:1 映射。
// 点赞是跨项目/动态/评论的共享池、后端 reactions 只认项目，映射脏，暂不接。
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/app_exception.dart';
import '../../core/network/dio_provider.dart';
import '../../domain/models/models.dart';
import '../dto/project_card_dto.dart';

class InteractionsApi {
  final Dio _dio;
  InteractionsApi(this._dio);

  /// 收藏 / 取消收藏。[on]=true → POST（201）；false → DELETE（204）。
  /// 需登录（后端 auth_required）；未登录会 401（拦截器尝试刷新，仍失败则抛）。
  Future<void> setFavorite(String projectId, bool on) async {
    try {
      if (on) {
        await _dio.post<dynamic>('/projects/$projectId/favorite');
      } else {
        await _dio.delete<dynamic>('/projects/$projectId/favorite');
      }
    } on DioException catch (e) {
      throw AppException.fromDio(e);
    }
  }

  /// 想看怎么做（主信号，红线：游客可用不设登录墙）。POST → 返回该项目最新累计需求数。
  /// [anonClientId] 游客必带（后端未登录时缺它 422）；登录用户后端取 token 身份，带上也无妨（登录归并）。
  /// 后端幂等：重复点按返回当前累计，不重复 +1。
  Future<int> recordHowToInterest(String projectId, {String? anonClientId}) async {
    try {
      final resp = await _dio.post<dynamic>(
        '/projects/$projectId/how-to-interest',
        data: {if (anonClientId != null) 'anon_client_id': anonClientId},
      );
      final data = resp.data;
      if (data is Map && data['how_to_interest_count'] != null) {
        final c = data['how_to_interest_count'];
        return c is int ? c : int.tryParse('$c') ?? 0;
      }
      return 0;
    } on DioException catch (e) {
      throw AppException.fromDio(e);
    }
  }

  /// 订阅 / 取消订阅实现线索。[on]=true → POST（201）；false → DELETE（204）。
  /// 需登录（后端 auth_required）。
  Future<void> setClueSubscription(String projectId, bool on) async {
    try {
      if (on) {
        await _dio.post<dynamic>('/projects/$projectId/clue-subscription');
      } else {
        await _dio.delete<dynamic>('/projects/$projectId/clue-subscription');
      }
    } on DioException catch (e) {
      throw AppException.fromDio(e);
    }
  }

  /// 关注 / 取关。[on]=true → POST（201）；false → DELETE（204）。需登录（auth_required）。
  Future<void> setFollow(String userId, bool on) async {
    try {
      if (on) {
        await _dio.post<dynamic>('/users/$userId/follow');
      } else {
        await _dio.delete<dynamic>('/users/$userId/follow');
      }
    } on DioException catch (e) {
      throw AppException.fromDio(e);
    }
  }

  /// GET /users/{userId}/following → ta 关注的人 id 列表（登录后回填自己的关注态）。
  Future<List<String>> listFollowingIds(String userId) async {
    try {
      final resp = await _dio.get<dynamic>('/users/$userId/following');
      final data = resp.data;
      final raw =
          data is Map ? (data['items'] ?? const <dynamic>[]) : (data ?? const <dynamic>[]);
      final items = raw is List ? raw : const <dynamic>[];
      return items
          .whereType<Map<dynamic, dynamic>>()
          .map((m) => m['id']?.toString())
          .whereType<String>()
          .toList();
    } on DioException catch (e) {
      throw AppException.fromDio(e);
    }
  }

  /// GET /me/favorites → 我收藏过的项目 id 列表（读通路：登录后回填收藏态）。
  /// 后端返回 {items:[ProjectCard...]}，这里只取 id（够点亮收藏心；卡片本身用不上）。
  Future<List<String>> listFavoriteIds() async {
    try {
      final resp = await _dio.get<dynamic>('/me/favorites');
      final data = resp.data;
      final rawItems =
          data is Map ? (data['items'] ?? const <dynamic>[]) : (data ?? const <dynamic>[]);
      final items = rawItems is List ? rawItems : const <dynamic>[];
      return items
          .whereType<Map<dynamic, dynamic>>()
          .map((m) => m['id']?.toString())
          .whereType<String>()
          .toList();
    } on DioException catch (e) {
      throw AppException.fromDio(e);
    }
  }

  /// GET /me/favorites → 我收藏过的项目「完整卡片」（含 author+counts，后端已批量填充）。
  /// 用于收藏屏真实展示 UUID 收藏（listFavoriteIds 只够点亮心，卡片本身用这个）。
  Future<List<Project>> listFavorites() async {
    try {
      final resp = await _dio.get<dynamic>('/me/favorites');
      final data = resp.data;
      final rawItems =
          data is Map ? (data['items'] ?? const <dynamic>[]) : (data ?? const <dynamic>[]);
      final items = rawItems is List ? rawItems : const <dynamic>[];
      return items
          .whereType<Map<dynamic, dynamic>>()
          .map((m) => projectFromCardJson(Map<String, dynamic>.from(m)))
          .toList();
    } on DioException catch (e) {
      throw AppException.fromDio(e);
    }
  }
}

final interactionsApiProvider = Provider<InteractionsApi>(
  (ref) => InteractionsApi(ref.watch(dioProvider)),
);
