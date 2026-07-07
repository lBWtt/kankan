// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'notification_item.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$NotificationItem {
  String get id;

  /// 5 类:'like' | 'comment' | 'follow' | 'favorite' | 'system'
  String get type;

  /// 触发者 ID(system 类为 null)
  String? get actorId;

  /// 跳转目标 ID:
  ///   - like → postId
  ///   - comment → hostId(postId 或 projectId)
  ///   - follow → userId
  ///   - favorite → projectId
  ///   - system → null(不跳转)
  String? get targetId;

  /// 评论类专用:宿主类型 'post' | 'project'(决定跳 comments 时传哪个 hostType)
  String? get hostType;

  /// 文案预览(评论类是评论内容截断,系统类是公告全文)
  String? get preview;

  /// 是否已读
  bool get read;

  /// 时间(毫秒)
  int get createdAtMs;

  /// Create a copy of NotificationItem
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $NotificationItemCopyWith<NotificationItem> get copyWith =>
      _$NotificationItemCopyWithImpl<NotificationItem>(
          this as NotificationItem, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is NotificationItem &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.type, type) || other.type == type) &&
            (identical(other.actorId, actorId) || other.actorId == actorId) &&
            (identical(other.targetId, targetId) ||
                other.targetId == targetId) &&
            (identical(other.hostType, hostType) ||
                other.hostType == hostType) &&
            (identical(other.preview, preview) || other.preview == preview) &&
            (identical(other.read, read) || other.read == read) &&
            (identical(other.createdAtMs, createdAtMs) ||
                other.createdAtMs == createdAtMs));
  }

  @override
  int get hashCode => Object.hash(runtimeType, id, type, actorId, targetId,
      hostType, preview, read, createdAtMs);

  @override
  String toString() {
    return 'NotificationItem(id: $id, type: $type, actorId: $actorId, targetId: $targetId, hostType: $hostType, preview: $preview, read: $read, createdAtMs: $createdAtMs)';
  }
}

/// @nodoc
abstract mixin class $NotificationItemCopyWith<$Res> {
  factory $NotificationItemCopyWith(
          NotificationItem value, $Res Function(NotificationItem) _then) =
      _$NotificationItemCopyWithImpl;
  @useResult
  $Res call(
      {String id,
      String type,
      String? actorId,
      String? targetId,
      String? hostType,
      String? preview,
      bool read,
      int createdAtMs});
}

/// @nodoc
class _$NotificationItemCopyWithImpl<$Res>
    implements $NotificationItemCopyWith<$Res> {
  _$NotificationItemCopyWithImpl(this._self, this._then);

  final NotificationItem _self;
  final $Res Function(NotificationItem) _then;

  /// Create a copy of NotificationItem
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? type = null,
    Object? actorId = freezed,
    Object? targetId = freezed,
    Object? hostType = freezed,
    Object? preview = freezed,
    Object? read = null,
    Object? createdAtMs = null,
  }) {
    return _then(_self.copyWith(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      type: null == type
          ? _self.type
          : type // ignore: cast_nullable_to_non_nullable
              as String,
      actorId: freezed == actorId
          ? _self.actorId
          : actorId // ignore: cast_nullable_to_non_nullable
              as String?,
      targetId: freezed == targetId
          ? _self.targetId
          : targetId // ignore: cast_nullable_to_non_nullable
              as String?,
      hostType: freezed == hostType
          ? _self.hostType
          : hostType // ignore: cast_nullable_to_non_nullable
              as String?,
      preview: freezed == preview
          ? _self.preview
          : preview // ignore: cast_nullable_to_non_nullable
              as String?,
      read: null == read
          ? _self.read
          : read // ignore: cast_nullable_to_non_nullable
              as bool,
      createdAtMs: null == createdAtMs
          ? _self.createdAtMs
          : createdAtMs // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

/// Adds pattern-matching-related methods to [NotificationItem].
extension NotificationItemPatterns on NotificationItem {
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
    TResult Function(_NotificationItem value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _NotificationItem() when $default != null:
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
    TResult Function(_NotificationItem value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _NotificationItem():
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
    TResult? Function(_NotificationItem value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _NotificationItem() when $default != null:
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
    TResult Function(String id, String type, String? actorId, String? targetId,
            String? hostType, String? preview, bool read, int createdAtMs)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _NotificationItem() when $default != null:
        return $default(_that.id, _that.type, _that.actorId, _that.targetId,
            _that.hostType, _that.preview, _that.read, _that.createdAtMs);
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
    TResult Function(String id, String type, String? actorId, String? targetId,
            String? hostType, String? preview, bool read, int createdAtMs)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _NotificationItem():
        return $default(_that.id, _that.type, _that.actorId, _that.targetId,
            _that.hostType, _that.preview, _that.read, _that.createdAtMs);
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
    TResult? Function(String id, String type, String? actorId, String? targetId,
            String? hostType, String? preview, bool read, int createdAtMs)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _NotificationItem() when $default != null:
        return $default(_that.id, _that.type, _that.actorId, _that.targetId,
            _that.hostType, _that.preview, _that.read, _that.createdAtMs);
      case _:
        return null;
    }
  }
}

/// @nodoc

class _NotificationItem implements NotificationItem {
  const _NotificationItem(
      {required this.id,
      required this.type,
      this.actorId,
      this.targetId,
      this.hostType,
      this.preview,
      this.read = false,
      required this.createdAtMs});

  @override
  final String id;

  /// 5 类:'like' | 'comment' | 'follow' | 'favorite' | 'system'
  @override
  final String type;

  /// 触发者 ID(system 类为 null)
  @override
  final String? actorId;

  /// 跳转目标 ID:
  ///   - like → postId
  ///   - comment → hostId(postId 或 projectId)
  ///   - follow → userId
  ///   - favorite → projectId
  ///   - system → null(不跳转)
  @override
  final String? targetId;

  /// 评论类专用:宿主类型 'post' | 'project'(决定跳 comments 时传哪个 hostType)
  @override
  final String? hostType;

  /// 文案预览(评论类是评论内容截断,系统类是公告全文)
  @override
  final String? preview;

  /// 是否已读
  @override
  @JsonKey()
  final bool read;

  /// 时间(毫秒)
  @override
  final int createdAtMs;

  /// Create a copy of NotificationItem
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$NotificationItemCopyWith<_NotificationItem> get copyWith =>
      __$NotificationItemCopyWithImpl<_NotificationItem>(this, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _NotificationItem &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.type, type) || other.type == type) &&
            (identical(other.actorId, actorId) || other.actorId == actorId) &&
            (identical(other.targetId, targetId) ||
                other.targetId == targetId) &&
            (identical(other.hostType, hostType) ||
                other.hostType == hostType) &&
            (identical(other.preview, preview) || other.preview == preview) &&
            (identical(other.read, read) || other.read == read) &&
            (identical(other.createdAtMs, createdAtMs) ||
                other.createdAtMs == createdAtMs));
  }

  @override
  int get hashCode => Object.hash(runtimeType, id, type, actorId, targetId,
      hostType, preview, read, createdAtMs);

  @override
  String toString() {
    return 'NotificationItem(id: $id, type: $type, actorId: $actorId, targetId: $targetId, hostType: $hostType, preview: $preview, read: $read, createdAtMs: $createdAtMs)';
  }
}

/// @nodoc
abstract mixin class _$NotificationItemCopyWith<$Res>
    implements $NotificationItemCopyWith<$Res> {
  factory _$NotificationItemCopyWith(
          _NotificationItem value, $Res Function(_NotificationItem) _then) =
      __$NotificationItemCopyWithImpl;
  @override
  @useResult
  $Res call(
      {String id,
      String type,
      String? actorId,
      String? targetId,
      String? hostType,
      String? preview,
      bool read,
      int createdAtMs});
}

/// @nodoc
class __$NotificationItemCopyWithImpl<$Res>
    implements _$NotificationItemCopyWith<$Res> {
  __$NotificationItemCopyWithImpl(this._self, this._then);

  final _NotificationItem _self;
  final $Res Function(_NotificationItem) _then;

  /// Create a copy of NotificationItem
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? id = null,
    Object? type = null,
    Object? actorId = freezed,
    Object? targetId = freezed,
    Object? hostType = freezed,
    Object? preview = freezed,
    Object? read = null,
    Object? createdAtMs = null,
  }) {
    return _then(_NotificationItem(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      type: null == type
          ? _self.type
          : type // ignore: cast_nullable_to_non_nullable
              as String,
      actorId: freezed == actorId
          ? _self.actorId
          : actorId // ignore: cast_nullable_to_non_nullable
              as String?,
      targetId: freezed == targetId
          ? _self.targetId
          : targetId // ignore: cast_nullable_to_non_nullable
              as String?,
      hostType: freezed == hostType
          ? _self.hostType
          : hostType // ignore: cast_nullable_to_non_nullable
              as String?,
      preview: freezed == preview
          ? _self.preview
          : preview // ignore: cast_nullable_to_non_nullable
              as String?,
      read: null == read
          ? _self.read
          : read // ignore: cast_nullable_to_non_nullable
              as bool,
      createdAtMs: null == createdAtMs
          ? _self.createdAtMs
          : createdAtMs // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

// dart format on
