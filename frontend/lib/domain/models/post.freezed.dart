// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'post.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$Post {
  String get id;

  /// 正文
  String get content;

  /// 作者 ID
  String get authorId;

  /// 可选图片(无视频 — 视频走 Project)
  List<MediaItem> get media;

  /// 话题标签(HANDOFF §6.2 — 真实 tags 字段)
  List<String> get tags;

  /// 引用的项目 ID(可选)
  String? get quoteProjectId;

  /// 点赞数(真实)
  int get likes;

  /// 评论数(真实)
  int get commentCount;

  /// 创建时间(毫秒)
  int get createdAtMs;

  /// Create a copy of Post
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $PostCopyWith<Post> get copyWith =>
      _$PostCopyWithImpl<Post>(this as Post, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is Post &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.content, content) || other.content == content) &&
            (identical(other.authorId, authorId) ||
                other.authorId == authorId) &&
            const DeepCollectionEquality().equals(other.media, media) &&
            const DeepCollectionEquality().equals(other.tags, tags) &&
            (identical(other.quoteProjectId, quoteProjectId) ||
                other.quoteProjectId == quoteProjectId) &&
            (identical(other.likes, likes) || other.likes == likes) &&
            (identical(other.commentCount, commentCount) ||
                other.commentCount == commentCount) &&
            (identical(other.createdAtMs, createdAtMs) ||
                other.createdAtMs == createdAtMs));
  }

  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      content,
      authorId,
      const DeepCollectionEquality().hash(media),
      const DeepCollectionEquality().hash(tags),
      quoteProjectId,
      likes,
      commentCount,
      createdAtMs);

  @override
  String toString() {
    return 'Post(id: $id, content: $content, authorId: $authorId, media: $media, tags: $tags, quoteProjectId: $quoteProjectId, likes: $likes, commentCount: $commentCount, createdAtMs: $createdAtMs)';
  }
}

/// @nodoc
abstract mixin class $PostCopyWith<$Res> {
  factory $PostCopyWith(Post value, $Res Function(Post) _then) =
      _$PostCopyWithImpl;
  @useResult
  $Res call(
      {String id,
      String content,
      String authorId,
      List<MediaItem> media,
      List<String> tags,
      String? quoteProjectId,
      int likes,
      int commentCount,
      int createdAtMs});
}

/// @nodoc
class _$PostCopyWithImpl<$Res> implements $PostCopyWith<$Res> {
  _$PostCopyWithImpl(this._self, this._then);

  final Post _self;
  final $Res Function(Post) _then;

  /// Create a copy of Post
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? content = null,
    Object? authorId = null,
    Object? media = null,
    Object? tags = null,
    Object? quoteProjectId = freezed,
    Object? likes = null,
    Object? commentCount = null,
    Object? createdAtMs = null,
  }) {
    return _then(_self.copyWith(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      content: null == content
          ? _self.content
          : content // ignore: cast_nullable_to_non_nullable
              as String,
      authorId: null == authorId
          ? _self.authorId
          : authorId // ignore: cast_nullable_to_non_nullable
              as String,
      media: null == media
          ? _self.media
          : media // ignore: cast_nullable_to_non_nullable
              as List<MediaItem>,
      tags: null == tags
          ? _self.tags
          : tags // ignore: cast_nullable_to_non_nullable
              as List<String>,
      quoteProjectId: freezed == quoteProjectId
          ? _self.quoteProjectId
          : quoteProjectId // ignore: cast_nullable_to_non_nullable
              as String?,
      likes: null == likes
          ? _self.likes
          : likes // ignore: cast_nullable_to_non_nullable
              as int,
      commentCount: null == commentCount
          ? _self.commentCount
          : commentCount // ignore: cast_nullable_to_non_nullable
              as int,
      createdAtMs: null == createdAtMs
          ? _self.createdAtMs
          : createdAtMs // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

/// Adds pattern-matching-related methods to [Post].
extension PostPatterns on Post {
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
    TResult Function(_Post value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _Post() when $default != null:
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
    TResult Function(_Post value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _Post():
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
    TResult? Function(_Post value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _Post() when $default != null:
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
            String content,
            String authorId,
            List<MediaItem> media,
            List<String> tags,
            String? quoteProjectId,
            int likes,
            int commentCount,
            int createdAtMs)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _Post() when $default != null:
        return $default(
            _that.id,
            _that.content,
            _that.authorId,
            _that.media,
            _that.tags,
            _that.quoteProjectId,
            _that.likes,
            _that.commentCount,
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
            String content,
            String authorId,
            List<MediaItem> media,
            List<String> tags,
            String? quoteProjectId,
            int likes,
            int commentCount,
            int createdAtMs)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _Post():
        return $default(
            _that.id,
            _that.content,
            _that.authorId,
            _that.media,
            _that.tags,
            _that.quoteProjectId,
            _that.likes,
            _that.commentCount,
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
            String content,
            String authorId,
            List<MediaItem> media,
            List<String> tags,
            String? quoteProjectId,
            int likes,
            int commentCount,
            int createdAtMs)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _Post() when $default != null:
        return $default(
            _that.id,
            _that.content,
            _that.authorId,
            _that.media,
            _that.tags,
            _that.quoteProjectId,
            _that.likes,
            _that.commentCount,
            _that.createdAtMs);
      case _:
        return null;
    }
  }
}

/// @nodoc

class _Post implements Post {
  const _Post(
      {required this.id,
      required this.content,
      required this.authorId,
      final List<MediaItem> media = const [],
      final List<String> tags = const [],
      this.quoteProjectId,
      this.likes = 0,
      this.commentCount = 0,
      required this.createdAtMs})
      : _media = media,
        _tags = tags;

  @override
  final String id;

  /// 正文
  @override
  final String content;

  /// 作者 ID
  @override
  final String authorId;

  /// 可选图片(无视频 — 视频走 Project)
  final List<MediaItem> _media;

  /// 可选图片(无视频 — 视频走 Project)
  @override
  @JsonKey()
  List<MediaItem> get media {
    if (_media is EqualUnmodifiableListView) return _media;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_media);
  }

  /// 话题标签(HANDOFF §6.2 — 真实 tags 字段)
  final List<String> _tags;

  /// 话题标签(HANDOFF §6.2 — 真实 tags 字段)
  @override
  @JsonKey()
  List<String> get tags {
    if (_tags is EqualUnmodifiableListView) return _tags;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_tags);
  }

  /// 引用的项目 ID(可选)
  @override
  final String? quoteProjectId;

  /// 点赞数(真实)
  @override
  @JsonKey()
  final int likes;

  /// 评论数(真实)
  @override
  @JsonKey()
  final int commentCount;

  /// 创建时间(毫秒)
  @override
  final int createdAtMs;

  /// Create a copy of Post
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$PostCopyWith<_Post> get copyWith =>
      __$PostCopyWithImpl<_Post>(this, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _Post &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.content, content) || other.content == content) &&
            (identical(other.authorId, authorId) ||
                other.authorId == authorId) &&
            const DeepCollectionEquality().equals(other._media, _media) &&
            const DeepCollectionEquality().equals(other._tags, _tags) &&
            (identical(other.quoteProjectId, quoteProjectId) ||
                other.quoteProjectId == quoteProjectId) &&
            (identical(other.likes, likes) || other.likes == likes) &&
            (identical(other.commentCount, commentCount) ||
                other.commentCount == commentCount) &&
            (identical(other.createdAtMs, createdAtMs) ||
                other.createdAtMs == createdAtMs));
  }

  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      content,
      authorId,
      const DeepCollectionEquality().hash(_media),
      const DeepCollectionEquality().hash(_tags),
      quoteProjectId,
      likes,
      commentCount,
      createdAtMs);

  @override
  String toString() {
    return 'Post(id: $id, content: $content, authorId: $authorId, media: $media, tags: $tags, quoteProjectId: $quoteProjectId, likes: $likes, commentCount: $commentCount, createdAtMs: $createdAtMs)';
  }
}

/// @nodoc
abstract mixin class _$PostCopyWith<$Res> implements $PostCopyWith<$Res> {
  factory _$PostCopyWith(_Post value, $Res Function(_Post) _then) =
      __$PostCopyWithImpl;
  @override
  @useResult
  $Res call(
      {String id,
      String content,
      String authorId,
      List<MediaItem> media,
      List<String> tags,
      String? quoteProjectId,
      int likes,
      int commentCount,
      int createdAtMs});
}

/// @nodoc
class __$PostCopyWithImpl<$Res> implements _$PostCopyWith<$Res> {
  __$PostCopyWithImpl(this._self, this._then);

  final _Post _self;
  final $Res Function(_Post) _then;

  /// Create a copy of Post
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? id = null,
    Object? content = null,
    Object? authorId = null,
    Object? media = null,
    Object? tags = null,
    Object? quoteProjectId = freezed,
    Object? likes = null,
    Object? commentCount = null,
    Object? createdAtMs = null,
  }) {
    return _then(_Post(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      content: null == content
          ? _self.content
          : content // ignore: cast_nullable_to_non_nullable
              as String,
      authorId: null == authorId
          ? _self.authorId
          : authorId // ignore: cast_nullable_to_non_nullable
              as String,
      media: null == media
          ? _self._media
          : media // ignore: cast_nullable_to_non_nullable
              as List<MediaItem>,
      tags: null == tags
          ? _self._tags
          : tags // ignore: cast_nullable_to_non_nullable
              as List<String>,
      quoteProjectId: freezed == quoteProjectId
          ? _self.quoteProjectId
          : quoteProjectId // ignore: cast_nullable_to_non_nullable
              as String?,
      likes: null == likes
          ? _self.likes
          : likes // ignore: cast_nullable_to_non_nullable
              as int,
      commentCount: null == commentCount
          ? _self.commentCount
          : commentCount // ignore: cast_nullable_to_non_nullable
              as int,
      createdAtMs: null == createdAtMs
          ? _self.createdAtMs
          : createdAtMs // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

// dart format on
