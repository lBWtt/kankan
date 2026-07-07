// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'user.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$KkUser {
  String get id;
  String get name;

  /// 头像 URL(null 用首字母 fallback)
  String? get avatar;

  /// 一句话简介
  String? get bio;

  /// 关注的人 ID 列表
  List<String> get followingIds;

  /// 粉丝 ID 列表
  List<String> get followerIds;

  /// Create a copy of KkUser
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $KkUserCopyWith<KkUser> get copyWith =>
      _$KkUserCopyWithImpl<KkUser>(this as KkUser, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is KkUser &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.avatar, avatar) || other.avatar == avatar) &&
            (identical(other.bio, bio) || other.bio == bio) &&
            const DeepCollectionEquality()
                .equals(other.followingIds, followingIds) &&
            const DeepCollectionEquality()
                .equals(other.followerIds, followerIds));
  }

  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      name,
      avatar,
      bio,
      const DeepCollectionEquality().hash(followingIds),
      const DeepCollectionEquality().hash(followerIds));

  @override
  String toString() {
    return 'KkUser(id: $id, name: $name, avatar: $avatar, bio: $bio, followingIds: $followingIds, followerIds: $followerIds)';
  }
}

/// @nodoc
abstract mixin class $KkUserCopyWith<$Res> {
  factory $KkUserCopyWith(KkUser value, $Res Function(KkUser) _then) =
      _$KkUserCopyWithImpl;
  @useResult
  $Res call(
      {String id,
      String name,
      String? avatar,
      String? bio,
      List<String> followingIds,
      List<String> followerIds});
}

/// @nodoc
class _$KkUserCopyWithImpl<$Res> implements $KkUserCopyWith<$Res> {
  _$KkUserCopyWithImpl(this._self, this._then);

  final KkUser _self;
  final $Res Function(KkUser) _then;

  /// Create a copy of KkUser
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? avatar = freezed,
    Object? bio = freezed,
    Object? followingIds = null,
    Object? followerIds = null,
  }) {
    return _then(_self.copyWith(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _self.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      avatar: freezed == avatar
          ? _self.avatar
          : avatar // ignore: cast_nullable_to_non_nullable
              as String?,
      bio: freezed == bio
          ? _self.bio
          : bio // ignore: cast_nullable_to_non_nullable
              as String?,
      followingIds: null == followingIds
          ? _self.followingIds
          : followingIds // ignore: cast_nullable_to_non_nullable
              as List<String>,
      followerIds: null == followerIds
          ? _self.followerIds
          : followerIds // ignore: cast_nullable_to_non_nullable
              as List<String>,
    ));
  }
}

/// Adds pattern-matching-related methods to [KkUser].
extension KkUserPatterns on KkUser {
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
    TResult Function(_KkUser value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _KkUser() when $default != null:
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
    TResult Function(_KkUser value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _KkUser():
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
    TResult? Function(_KkUser value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _KkUser() when $default != null:
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
    TResult Function(String id, String name, String? avatar, String? bio,
            List<String> followingIds, List<String> followerIds)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _KkUser() when $default != null:
        return $default(_that.id, _that.name, _that.avatar, _that.bio,
            _that.followingIds, _that.followerIds);
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
    TResult Function(String id, String name, String? avatar, String? bio,
            List<String> followingIds, List<String> followerIds)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _KkUser():
        return $default(_that.id, _that.name, _that.avatar, _that.bio,
            _that.followingIds, _that.followerIds);
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
    TResult? Function(String id, String name, String? avatar, String? bio,
            List<String> followingIds, List<String> followerIds)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _KkUser() when $default != null:
        return $default(_that.id, _that.name, _that.avatar, _that.bio,
            _that.followingIds, _that.followerIds);
      case _:
        return null;
    }
  }
}

/// @nodoc

class _KkUser implements KkUser {
  const _KkUser(
      {required this.id,
      required this.name,
      this.avatar,
      this.bio,
      final List<String> followingIds = const [],
      final List<String> followerIds = const []})
      : _followingIds = followingIds,
        _followerIds = followerIds;

  @override
  final String id;
  @override
  final String name;

  /// 头像 URL(null 用首字母 fallback)
  @override
  final String? avatar;

  /// 一句话简介
  @override
  final String? bio;

  /// 关注的人 ID 列表
  final List<String> _followingIds;

  /// 关注的人 ID 列表
  @override
  @JsonKey()
  List<String> get followingIds {
    if (_followingIds is EqualUnmodifiableListView) return _followingIds;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_followingIds);
  }

  /// 粉丝 ID 列表
  final List<String> _followerIds;

  /// 粉丝 ID 列表
  @override
  @JsonKey()
  List<String> get followerIds {
    if (_followerIds is EqualUnmodifiableListView) return _followerIds;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_followerIds);
  }

  /// Create a copy of KkUser
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$KkUserCopyWith<_KkUser> get copyWith =>
      __$KkUserCopyWithImpl<_KkUser>(this, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _KkUser &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.avatar, avatar) || other.avatar == avatar) &&
            (identical(other.bio, bio) || other.bio == bio) &&
            const DeepCollectionEquality()
                .equals(other._followingIds, _followingIds) &&
            const DeepCollectionEquality()
                .equals(other._followerIds, _followerIds));
  }

  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      name,
      avatar,
      bio,
      const DeepCollectionEquality().hash(_followingIds),
      const DeepCollectionEquality().hash(_followerIds));

  @override
  String toString() {
    return 'KkUser(id: $id, name: $name, avatar: $avatar, bio: $bio, followingIds: $followingIds, followerIds: $followerIds)';
  }
}

/// @nodoc
abstract mixin class _$KkUserCopyWith<$Res> implements $KkUserCopyWith<$Res> {
  factory _$KkUserCopyWith(_KkUser value, $Res Function(_KkUser) _then) =
      __$KkUserCopyWithImpl;
  @override
  @useResult
  $Res call(
      {String id,
      String name,
      String? avatar,
      String? bio,
      List<String> followingIds,
      List<String> followerIds});
}

/// @nodoc
class __$KkUserCopyWithImpl<$Res> implements _$KkUserCopyWith<$Res> {
  __$KkUserCopyWithImpl(this._self, this._then);

  final _KkUser _self;
  final $Res Function(_KkUser) _then;

  /// Create a copy of KkUser
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? avatar = freezed,
    Object? bio = freezed,
    Object? followingIds = null,
    Object? followerIds = null,
  }) {
    return _then(_KkUser(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _self.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      avatar: freezed == avatar
          ? _self.avatar
          : avatar // ignore: cast_nullable_to_non_nullable
              as String?,
      bio: freezed == bio
          ? _self.bio
          : bio // ignore: cast_nullable_to_non_nullable
              as String?,
      followingIds: null == followingIds
          ? _self._followingIds
          : followingIds // ignore: cast_nullable_to_non_nullable
              as List<String>,
      followerIds: null == followerIds
          ? _self._followerIds
          : followerIds // ignore: cast_nullable_to_non_nullable
              as List<String>,
    ));
  }
}

// dart format on
