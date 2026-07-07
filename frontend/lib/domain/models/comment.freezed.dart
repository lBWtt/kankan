// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'comment.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$Comment {
  String get id;

  /// 宿主类型 'project' | 'post'
  String get hostType;

  /// 宿主 ID(project.id / post.id)
  String get hostId;

  /// 评论者 ID
  String get authorId;

  /// 正文
  String get content;

  /// 点赞数(真实)
  int get likes;

  /// 楼中楼回复(简化:同结构 List<Comment>)
  List<Comment> get replies;

  /// 创建时间(毫秒)
  int get createdAtMs;

  /// Create a copy of Comment
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $CommentCopyWith<Comment> get copyWith =>
      _$CommentCopyWithImpl<Comment>(this as Comment, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is Comment &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.hostType, hostType) ||
                other.hostType == hostType) &&
            (identical(other.hostId, hostId) || other.hostId == hostId) &&
            (identical(other.authorId, authorId) ||
                other.authorId == authorId) &&
            (identical(other.content, content) || other.content == content) &&
            (identical(other.likes, likes) || other.likes == likes) &&
            const DeepCollectionEquality().equals(other.replies, replies) &&
            (identical(other.createdAtMs, createdAtMs) ||
                other.createdAtMs == createdAtMs));
  }

  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      hostType,
      hostId,
      authorId,
      content,
      likes,
      const DeepCollectionEquality().hash(replies),
      createdAtMs);

  @override
  String toString() {
    return 'Comment(id: $id, hostType: $hostType, hostId: $hostId, authorId: $authorId, content: $content, likes: $likes, replies: $replies, createdAtMs: $createdAtMs)';
  }
}

/// @nodoc
abstract mixin class $CommentCopyWith<$Res> {
  factory $CommentCopyWith(Comment value, $Res Function(Comment) _then) =
      _$CommentCopyWithImpl;
  @useResult
  $Res call(
      {String id,
      String hostType,
      String hostId,
      String authorId,
      String content,
      int likes,
      List<Comment> replies,
      int createdAtMs});
}

/// @nodoc
class _$CommentCopyWithImpl<$Res> implements $CommentCopyWith<$Res> {
  _$CommentCopyWithImpl(this._self, this._then);

  final Comment _self;
  final $Res Function(Comment) _then;

  /// Create a copy of Comment
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? hostType = null,
    Object? hostId = null,
    Object? authorId = null,
    Object? content = null,
    Object? likes = null,
    Object? replies = null,
    Object? createdAtMs = null,
  }) {
    return _then(_self.copyWith(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      hostType: null == hostType
          ? _self.hostType
          : hostType // ignore: cast_nullable_to_non_nullable
              as String,
      hostId: null == hostId
          ? _self.hostId
          : hostId // ignore: cast_nullable_to_non_nullable
              as String,
      authorId: null == authorId
          ? _self.authorId
          : authorId // ignore: cast_nullable_to_non_nullable
              as String,
      content: null == content
          ? _self.content
          : content // ignore: cast_nullable_to_non_nullable
              as String,
      likes: null == likes
          ? _self.likes
          : likes // ignore: cast_nullable_to_non_nullable
              as int,
      replies: null == replies
          ? _self.replies
          : replies // ignore: cast_nullable_to_non_nullable
              as List<Comment>,
      createdAtMs: null == createdAtMs
          ? _self.createdAtMs
          : createdAtMs // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

/// Adds pattern-matching-related methods to [Comment].
extension CommentPatterns on Comment {
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
    TResult Function(_Comment value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _Comment() when $default != null:
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
    TResult Function(_Comment value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _Comment():
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
    TResult? Function(_Comment value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _Comment() when $default != null:
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
    TResult Function(String id, String hostType, String hostId, String authorId,
            String content, int likes, List<Comment> replies, int createdAtMs)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _Comment() when $default != null:
        return $default(_that.id, _that.hostType, _that.hostId, _that.authorId,
            _that.content, _that.likes, _that.replies, _that.createdAtMs);
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
    TResult Function(String id, String hostType, String hostId, String authorId,
            String content, int likes, List<Comment> replies, int createdAtMs)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _Comment():
        return $default(_that.id, _that.hostType, _that.hostId, _that.authorId,
            _that.content, _that.likes, _that.replies, _that.createdAtMs);
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
            String hostType,
            String hostId,
            String authorId,
            String content,
            int likes,
            List<Comment> replies,
            int createdAtMs)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _Comment() when $default != null:
        return $default(_that.id, _that.hostType, _that.hostId, _that.authorId,
            _that.content, _that.likes, _that.replies, _that.createdAtMs);
      case _:
        return null;
    }
  }
}

/// @nodoc

class _Comment implements Comment {
  const _Comment(
      {required this.id,
      required this.hostType,
      required this.hostId,
      required this.authorId,
      required this.content,
      this.likes = 0,
      final List<Comment> replies = const [],
      required this.createdAtMs})
      : _replies = replies;

  @override
  final String id;

  /// 宿主类型 'project' | 'post'
  @override
  final String hostType;

  /// 宿主 ID(project.id / post.id)
  @override
  final String hostId;

  /// 评论者 ID
  @override
  final String authorId;

  /// 正文
  @override
  final String content;

  /// 点赞数(真实)
  @override
  @JsonKey()
  final int likes;

  /// 楼中楼回复(简化:同结构 List<Comment>)
  final List<Comment> _replies;

  /// 楼中楼回复(简化:同结构 List<Comment>)
  @override
  @JsonKey()
  List<Comment> get replies {
    if (_replies is EqualUnmodifiableListView) return _replies;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_replies);
  }

  /// 创建时间(毫秒)
  @override
  final int createdAtMs;

  /// Create a copy of Comment
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$CommentCopyWith<_Comment> get copyWith =>
      __$CommentCopyWithImpl<_Comment>(this, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _Comment &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.hostType, hostType) ||
                other.hostType == hostType) &&
            (identical(other.hostId, hostId) || other.hostId == hostId) &&
            (identical(other.authorId, authorId) ||
                other.authorId == authorId) &&
            (identical(other.content, content) || other.content == content) &&
            (identical(other.likes, likes) || other.likes == likes) &&
            const DeepCollectionEquality().equals(other._replies, _replies) &&
            (identical(other.createdAtMs, createdAtMs) ||
                other.createdAtMs == createdAtMs));
  }

  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      hostType,
      hostId,
      authorId,
      content,
      likes,
      const DeepCollectionEquality().hash(_replies),
      createdAtMs);

  @override
  String toString() {
    return 'Comment(id: $id, hostType: $hostType, hostId: $hostId, authorId: $authorId, content: $content, likes: $likes, replies: $replies, createdAtMs: $createdAtMs)';
  }
}

/// @nodoc
abstract mixin class _$CommentCopyWith<$Res> implements $CommentCopyWith<$Res> {
  factory _$CommentCopyWith(_Comment value, $Res Function(_Comment) _then) =
      __$CommentCopyWithImpl;
  @override
  @useResult
  $Res call(
      {String id,
      String hostType,
      String hostId,
      String authorId,
      String content,
      int likes,
      List<Comment> replies,
      int createdAtMs});
}

/// @nodoc
class __$CommentCopyWithImpl<$Res> implements _$CommentCopyWith<$Res> {
  __$CommentCopyWithImpl(this._self, this._then);

  final _Comment _self;
  final $Res Function(_Comment) _then;

  /// Create a copy of Comment
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? id = null,
    Object? hostType = null,
    Object? hostId = null,
    Object? authorId = null,
    Object? content = null,
    Object? likes = null,
    Object? replies = null,
    Object? createdAtMs = null,
  }) {
    return _then(_Comment(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      hostType: null == hostType
          ? _self.hostType
          : hostType // ignore: cast_nullable_to_non_nullable
              as String,
      hostId: null == hostId
          ? _self.hostId
          : hostId // ignore: cast_nullable_to_non_nullable
              as String,
      authorId: null == authorId
          ? _self.authorId
          : authorId // ignore: cast_nullable_to_non_nullable
              as String,
      content: null == content
          ? _self.content
          : content // ignore: cast_nullable_to_non_nullable
              as String,
      likes: null == likes
          ? _self.likes
          : likes // ignore: cast_nullable_to_non_nullable
              as int,
      replies: null == replies
          ? _self._replies
          : replies // ignore: cast_nullable_to_non_nullable
              as List<Comment>,
      createdAtMs: null == createdAtMs
          ? _self.createdAtMs
          : createdAtMs // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

// dart format on
