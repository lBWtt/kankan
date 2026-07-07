// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'project.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$Project {
  String get id;

  /// 标题
  String get title;

  /// 一句话价值(detail 页标题下显示)
  String get summary;

  /// 作者 ID
  String get authorId;

  /// 成果区(media/repo/io/text 组合)
  ResultData get resultData;

  /// 动作区(take/go/how 任意组合,一行一个)。空 → 动作区整块不显示。
  List<ActionItem> get actions;

  /// 标签(HANDOFF §6.2 — Web 版没有,Flutter 从零做对)
  List<String> get tags;

  /// 作者的话(夹在成果与动作之间)。空 → 整块隐藏(连标题)。
  String? get authorNote;

  /// 领域(用于 kankan 屏筛选)— 'ai_image' / 'ai_video' / 'web' / 'app' /
  /// 'tool' / 'opensource' / 'prompt'
  String get domain;

  /// 点赞数(真实)
  int get likes;

  /// 评论数(真实,与 comments 列表长度一致 — HANDOFF §6.10)
  int get commentCount;

  /// 被拿走次数(take 成功 +1,HANDOFF §2.2)
  int get takeawayCount;

  /// 仓库 star 数(repo 项目用,与 RepoInfo.stars 同源)
  int get repoStars;

  /// 创建时间(毫秒)
  int get createdAtMs;

  /// Create a copy of Project
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $ProjectCopyWith<Project> get copyWith =>
      _$ProjectCopyWithImpl<Project>(this as Project, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is Project &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.title, title) || other.title == title) &&
            (identical(other.summary, summary) || other.summary == summary) &&
            (identical(other.authorId, authorId) ||
                other.authorId == authorId) &&
            (identical(other.resultData, resultData) ||
                other.resultData == resultData) &&
            const DeepCollectionEquality().equals(other.actions, actions) &&
            const DeepCollectionEquality().equals(other.tags, tags) &&
            (identical(other.authorNote, authorNote) ||
                other.authorNote == authorNote) &&
            (identical(other.domain, domain) || other.domain == domain) &&
            (identical(other.likes, likes) || other.likes == likes) &&
            (identical(other.commentCount, commentCount) ||
                other.commentCount == commentCount) &&
            (identical(other.takeawayCount, takeawayCount) ||
                other.takeawayCount == takeawayCount) &&
            (identical(other.repoStars, repoStars) ||
                other.repoStars == repoStars) &&
            (identical(other.createdAtMs, createdAtMs) ||
                other.createdAtMs == createdAtMs));
  }

  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      title,
      summary,
      authorId,
      resultData,
      const DeepCollectionEquality().hash(actions),
      const DeepCollectionEquality().hash(tags),
      authorNote,
      domain,
      likes,
      commentCount,
      takeawayCount,
      repoStars,
      createdAtMs);

  @override
  String toString() {
    return 'Project(id: $id, title: $title, summary: $summary, authorId: $authorId, resultData: $resultData, actions: $actions, tags: $tags, authorNote: $authorNote, domain: $domain, likes: $likes, commentCount: $commentCount, takeawayCount: $takeawayCount, repoStars: $repoStars, createdAtMs: $createdAtMs)';
  }
}

/// @nodoc
abstract mixin class $ProjectCopyWith<$Res> {
  factory $ProjectCopyWith(Project value, $Res Function(Project) _then) =
      _$ProjectCopyWithImpl;
  @useResult
  $Res call(
      {String id,
      String title,
      String summary,
      String authorId,
      ResultData resultData,
      List<ActionItem> actions,
      List<String> tags,
      String? authorNote,
      String domain,
      int likes,
      int commentCount,
      int takeawayCount,
      int repoStars,
      int createdAtMs});

  $ResultDataCopyWith<$Res> get resultData;
}

/// @nodoc
class _$ProjectCopyWithImpl<$Res> implements $ProjectCopyWith<$Res> {
  _$ProjectCopyWithImpl(this._self, this._then);

  final Project _self;
  final $Res Function(Project) _then;

  /// Create a copy of Project
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? title = null,
    Object? summary = null,
    Object? authorId = null,
    Object? resultData = null,
    Object? actions = null,
    Object? tags = null,
    Object? authorNote = freezed,
    Object? domain = null,
    Object? likes = null,
    Object? commentCount = null,
    Object? takeawayCount = null,
    Object? repoStars = null,
    Object? createdAtMs = null,
  }) {
    return _then(_self.copyWith(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      title: null == title
          ? _self.title
          : title // ignore: cast_nullable_to_non_nullable
              as String,
      summary: null == summary
          ? _self.summary
          : summary // ignore: cast_nullable_to_non_nullable
              as String,
      authorId: null == authorId
          ? _self.authorId
          : authorId // ignore: cast_nullable_to_non_nullable
              as String,
      resultData: null == resultData
          ? _self.resultData
          : resultData // ignore: cast_nullable_to_non_nullable
              as ResultData,
      actions: null == actions
          ? _self.actions
          : actions // ignore: cast_nullable_to_non_nullable
              as List<ActionItem>,
      tags: null == tags
          ? _self.tags
          : tags // ignore: cast_nullable_to_non_nullable
              as List<String>,
      authorNote: freezed == authorNote
          ? _self.authorNote
          : authorNote // ignore: cast_nullable_to_non_nullable
              as String?,
      domain: null == domain
          ? _self.domain
          : domain // ignore: cast_nullable_to_non_nullable
              as String,
      likes: null == likes
          ? _self.likes
          : likes // ignore: cast_nullable_to_non_nullable
              as int,
      commentCount: null == commentCount
          ? _self.commentCount
          : commentCount // ignore: cast_nullable_to_non_nullable
              as int,
      takeawayCount: null == takeawayCount
          ? _self.takeawayCount
          : takeawayCount // ignore: cast_nullable_to_non_nullable
              as int,
      repoStars: null == repoStars
          ? _self.repoStars
          : repoStars // ignore: cast_nullable_to_non_nullable
              as int,
      createdAtMs: null == createdAtMs
          ? _self.createdAtMs
          : createdAtMs // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }

  /// Create a copy of Project
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $ResultDataCopyWith<$Res> get resultData {
    return $ResultDataCopyWith<$Res>(_self.resultData, (value) {
      return _then(_self.copyWith(resultData: value));
    });
  }
}

/// Adds pattern-matching-related methods to [Project].
extension ProjectPatterns on Project {
  /// A variant of `map` that fallback to returning `orElse`.
  ///
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case final Subclass value:
  ///     return ...;
  ///   case _:
  ///     return orElse();
  /// }
  /// ```

  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>(
    TResult Function(_Project value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _Project() when $default != null:
        return $default(_that);
      case _:
        return orElse();
    }
  }

  /// A `switch`-like method, using callbacks.
  ///
  /// Callbacks receives the raw object, upcasted.
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case final Subclass value:
  ///     return ...;
  ///   case final Subclass2 value:
  ///     return ...;
  /// }
  /// ```

  @optionalTypeArgs
  TResult map<TResult extends Object?>(
    TResult Function(_Project value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _Project():
        return $default(_that);
      case _:
        throw StateError('Unexpected subclass');
    }
  }

  /// A variant of `map` that fallback to returning `null`.
  ///
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case final Subclass value:
  ///     return ...;
  ///   case _:
  ///     return null;
  /// }
  /// ```

  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>(
    TResult? Function(_Project value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _Project() when $default != null:
        return $default(_that);
      case _:
        return null;
    }
  }

  /// A variant of `when` that fallback to an `orElse` callback.
  ///
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case Subclass(:final field):
  ///     return ...;
  ///   case _:
  ///     return orElse();
  /// }
  /// ```

  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>(
    TResult Function(
            String id,
            String title,
            String summary,
            String authorId,
            ResultData resultData,
            List<ActionItem> actions,
            List<String> tags,
            String? authorNote,
            String domain,
            int likes,
            int commentCount,
            int takeawayCount,
            int repoStars,
            int createdAtMs)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _Project() when $default != null:
        return $default(
            _that.id,
            _that.title,
            _that.summary,
            _that.authorId,
            _that.resultData,
            _that.actions,
            _that.tags,
            _that.authorNote,
            _that.domain,
            _that.likes,
            _that.commentCount,
            _that.takeawayCount,
            _that.repoStars,
            _that.createdAtMs);
      case _:
        return orElse();
    }
  }

  /// A `switch`-like method, using callbacks.
  ///
  /// As opposed to `map`, this offers destructuring.
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case Subclass(:final field):
  ///     return ...;
  ///   case Subclass2(:final field2):
  ///     return ...;
  /// }
  /// ```

  @optionalTypeArgs
  TResult when<TResult extends Object?>(
    TResult Function(
            String id,
            String title,
            String summary,
            String authorId,
            ResultData resultData,
            List<ActionItem> actions,
            List<String> tags,
            String? authorNote,
            String domain,
            int likes,
            int commentCount,
            int takeawayCount,
            int repoStars,
            int createdAtMs)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _Project():
        return $default(
            _that.id,
            _that.title,
            _that.summary,
            _that.authorId,
            _that.resultData,
            _that.actions,
            _that.tags,
            _that.authorNote,
            _that.domain,
            _that.likes,
            _that.commentCount,
            _that.takeawayCount,
            _that.repoStars,
            _that.createdAtMs);
      case _:
        throw StateError('Unexpected subclass');
    }
  }

  /// A variant of `when` that fallback to returning `null`
  ///
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case Subclass(:final field):
  ///     return ...;
  ///   case _:
  ///     return null;
  /// }
  /// ```

  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>(
    TResult? Function(
            String id,
            String title,
            String summary,
            String authorId,
            ResultData resultData,
            List<ActionItem> actions,
            List<String> tags,
            String? authorNote,
            String domain,
            int likes,
            int commentCount,
            int takeawayCount,
            int repoStars,
            int createdAtMs)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _Project() when $default != null:
        return $default(
            _that.id,
            _that.title,
            _that.summary,
            _that.authorId,
            _that.resultData,
            _that.actions,
            _that.tags,
            _that.authorNote,
            _that.domain,
            _that.likes,
            _that.commentCount,
            _that.takeawayCount,
            _that.repoStars,
            _that.createdAtMs);
      case _:
        return null;
    }
  }
}

/// @nodoc

class _Project implements Project {
  const _Project(
      {required this.id,
      required this.title,
      required this.summary,
      required this.authorId,
      required this.resultData,
      final List<ActionItem> actions = const [],
      final List<String> tags = const [],
      this.authorNote,
      required this.domain,
      this.likes = 0,
      this.commentCount = 0,
      this.takeawayCount = 0,
      this.repoStars = 0,
      required this.createdAtMs})
      : _actions = actions,
        _tags = tags;

  @override
  final String id;

  /// 标题
  @override
  final String title;

  /// 一句话价值(detail 页标题下显示)
  @override
  final String summary;

  /// 作者 ID
  @override
  final String authorId;

  /// 成果区(media/repo/io/text 组合)
  @override
  final ResultData resultData;

  /// 动作区(take/go/how 任意组合,一行一个)。空 → 动作区整块不显示。
  final List<ActionItem> _actions;

  /// 动作区(take/go/how 任意组合,一行一个)。空 → 动作区整块不显示。
  @override
  @JsonKey()
  List<ActionItem> get actions {
    if (_actions is EqualUnmodifiableListView) return _actions;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_actions);
  }

  /// 标签(HANDOFF §6.2 — Web 版没有,Flutter 从零做对)
  final List<String> _tags;

  /// 标签(HANDOFF §6.2 — Web 版没有,Flutter 从零做对)
  @override
  @JsonKey()
  List<String> get tags {
    if (_tags is EqualUnmodifiableListView) return _tags;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_tags);
  }

  /// 作者的话(夹在成果与动作之间)。空 → 整块隐藏(连标题)。
  @override
  final String? authorNote;

  /// 领域(用于 kankan 屏筛选)— 'ai_image' / 'ai_video' / 'web' / 'app' /
  /// 'tool' / 'opensource' / 'prompt'
  @override
  final String domain;

  /// 点赞数(真实)
  @override
  @JsonKey()
  final int likes;

  /// 评论数(真实,与 comments 列表长度一致 — HANDOFF §6.10)
  @override
  @JsonKey()
  final int commentCount;

  /// 被拿走次数(take 成功 +1,HANDOFF §2.2)
  @override
  @JsonKey()
  final int takeawayCount;

  /// 仓库 star 数(repo 项目用,与 RepoInfo.stars 同源)
  @override
  @JsonKey()
  final int repoStars;

  /// 创建时间(毫秒)
  @override
  final int createdAtMs;

  /// Create a copy of Project
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$ProjectCopyWith<_Project> get copyWith =>
      __$ProjectCopyWithImpl<_Project>(this, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _Project &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.title, title) || other.title == title) &&
            (identical(other.summary, summary) || other.summary == summary) &&
            (identical(other.authorId, authorId) ||
                other.authorId == authorId) &&
            (identical(other.resultData, resultData) ||
                other.resultData == resultData) &&
            const DeepCollectionEquality().equals(other._actions, _actions) &&
            const DeepCollectionEquality().equals(other._tags, _tags) &&
            (identical(other.authorNote, authorNote) ||
                other.authorNote == authorNote) &&
            (identical(other.domain, domain) || other.domain == domain) &&
            (identical(other.likes, likes) || other.likes == likes) &&
            (identical(other.commentCount, commentCount) ||
                other.commentCount == commentCount) &&
            (identical(other.takeawayCount, takeawayCount) ||
                other.takeawayCount == takeawayCount) &&
            (identical(other.repoStars, repoStars) ||
                other.repoStars == repoStars) &&
            (identical(other.createdAtMs, createdAtMs) ||
                other.createdAtMs == createdAtMs));
  }

  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      title,
      summary,
      authorId,
      resultData,
      const DeepCollectionEquality().hash(_actions),
      const DeepCollectionEquality().hash(_tags),
      authorNote,
      domain,
      likes,
      commentCount,
      takeawayCount,
      repoStars,
      createdAtMs);

  @override
  String toString() {
    return 'Project(id: $id, title: $title, summary: $summary, authorId: $authorId, resultData: $resultData, actions: $actions, tags: $tags, authorNote: $authorNote, domain: $domain, likes: $likes, commentCount: $commentCount, takeawayCount: $takeawayCount, repoStars: $repoStars, createdAtMs: $createdAtMs)';
  }
}

/// @nodoc
abstract mixin class _$ProjectCopyWith<$Res> implements $ProjectCopyWith<$Res> {
  factory _$ProjectCopyWith(_Project value, $Res Function(_Project) _then) =
      __$ProjectCopyWithImpl;
  @override
  @useResult
  $Res call(
      {String id,
      String title,
      String summary,
      String authorId,
      ResultData resultData,
      List<ActionItem> actions,
      List<String> tags,
      String? authorNote,
      String domain,
      int likes,
      int commentCount,
      int takeawayCount,
      int repoStars,
      int createdAtMs});

  @override
  $ResultDataCopyWith<$Res> get resultData;
}

/// @nodoc
class __$ProjectCopyWithImpl<$Res> implements _$ProjectCopyWith<$Res> {
  __$ProjectCopyWithImpl(this._self, this._then);

  final _Project _self;
  final $Res Function(_Project) _then;

  /// Create a copy of Project
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? id = null,
    Object? title = null,
    Object? summary = null,
    Object? authorId = null,
    Object? resultData = null,
    Object? actions = null,
    Object? tags = null,
    Object? authorNote = freezed,
    Object? domain = null,
    Object? likes = null,
    Object? commentCount = null,
    Object? takeawayCount = null,
    Object? repoStars = null,
    Object? createdAtMs = null,
  }) {
    return _then(_Project(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      title: null == title
          ? _self.title
          : title // ignore: cast_nullable_to_non_nullable
              as String,
      summary: null == summary
          ? _self.summary
          : summary // ignore: cast_nullable_to_non_nullable
              as String,
      authorId: null == authorId
          ? _self.authorId
          : authorId // ignore: cast_nullable_to_non_nullable
              as String,
      resultData: null == resultData
          ? _self.resultData
          : resultData // ignore: cast_nullable_to_non_nullable
              as ResultData,
      actions: null == actions
          ? _self._actions
          : actions // ignore: cast_nullable_to_non_nullable
              as List<ActionItem>,
      tags: null == tags
          ? _self._tags
          : tags // ignore: cast_nullable_to_non_nullable
              as List<String>,
      authorNote: freezed == authorNote
          ? _self.authorNote
          : authorNote // ignore: cast_nullable_to_non_nullable
              as String?,
      domain: null == domain
          ? _self.domain
          : domain // ignore: cast_nullable_to_non_nullable
              as String,
      likes: null == likes
          ? _self.likes
          : likes // ignore: cast_nullable_to_non_nullable
              as int,
      commentCount: null == commentCount
          ? _self.commentCount
          : commentCount // ignore: cast_nullable_to_non_nullable
              as int,
      takeawayCount: null == takeawayCount
          ? _self.takeawayCount
          : takeawayCount // ignore: cast_nullable_to_non_nullable
              as int,
      repoStars: null == repoStars
          ? _self.repoStars
          : repoStars // ignore: cast_nullable_to_non_nullable
              as int,
      createdAtMs: null == createdAtMs
          ? _self.createdAtMs
          : createdAtMs // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }

  /// Create a copy of Project
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $ResultDataCopyWith<$Res> get resultData {
    return $ResultDataCopyWith<$Res>(_self.resultData, (value) {
      return _then(_self.copyWith(resultData: value));
    });
  }
}

// dart format on
