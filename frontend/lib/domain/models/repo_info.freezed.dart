// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'repo_info.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$RepoInfo {
  /// 仓库短名,如 "flutter"
  String get name;

  /// 全名,如 "flutter/flutter"
  String get fullName;

  /// star 数(真实,禁编造 — HANDOFF §6.10)
  int get stars;

  /// 主语言,如 "Dart"
  String get language;

  /// 仓库 URL
  String get url;

  /// 可选描述
  String? get description;

  /// Create a copy of RepoInfo
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $RepoInfoCopyWith<RepoInfo> get copyWith =>
      _$RepoInfoCopyWithImpl<RepoInfo>(this as RepoInfo, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is RepoInfo &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.fullName, fullName) ||
                other.fullName == fullName) &&
            (identical(other.stars, stars) || other.stars == stars) &&
            (identical(other.language, language) ||
                other.language == language) &&
            (identical(other.url, url) || other.url == url) &&
            (identical(other.description, description) ||
                other.description == description));
  }

  @override
  int get hashCode => Object.hash(
      runtimeType, name, fullName, stars, language, url, description);

  @override
  String toString() {
    return 'RepoInfo(name: $name, fullName: $fullName, stars: $stars, language: $language, url: $url, description: $description)';
  }
}

/// @nodoc
abstract mixin class $RepoInfoCopyWith<$Res> {
  factory $RepoInfoCopyWith(RepoInfo value, $Res Function(RepoInfo) _then) =
      _$RepoInfoCopyWithImpl;
  @useResult
  $Res call(
      {String name,
      String fullName,
      int stars,
      String language,
      String url,
      String? description});
}

/// @nodoc
class _$RepoInfoCopyWithImpl<$Res> implements $RepoInfoCopyWith<$Res> {
  _$RepoInfoCopyWithImpl(this._self, this._then);

  final RepoInfo _self;
  final $Res Function(RepoInfo) _then;

  /// Create a copy of RepoInfo
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? name = null,
    Object? fullName = null,
    Object? stars = null,
    Object? language = null,
    Object? url = null,
    Object? description = freezed,
  }) {
    return _then(_self.copyWith(
      name: null == name
          ? _self.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      fullName: null == fullName
          ? _self.fullName
          : fullName // ignore: cast_nullable_to_non_nullable
              as String,
      stars: null == stars
          ? _self.stars
          : stars // ignore: cast_nullable_to_non_nullable
              as int,
      language: null == language
          ? _self.language
          : language // ignore: cast_nullable_to_non_nullable
              as String,
      url: null == url
          ? _self.url
          : url // ignore: cast_nullable_to_non_nullable
              as String,
      description: freezed == description
          ? _self.description
          : description // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// Adds pattern-matching-related methods to [RepoInfo].
extension RepoInfoPatterns on RepoInfo {
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
    TResult Function(_RepoInfo value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _RepoInfo() when $default != null:
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
    TResult Function(_RepoInfo value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _RepoInfo():
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
    TResult? Function(_RepoInfo value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _RepoInfo() when $default != null:
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
    TResult Function(String name, String fullName, int stars, String language,
            String url, String? description)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _RepoInfo() when $default != null:
        return $default(_that.name, _that.fullName, _that.stars, _that.language,
            _that.url, _that.description);
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
    TResult Function(String name, String fullName, int stars, String language,
            String url, String? description)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _RepoInfo():
        return $default(_that.name, _that.fullName, _that.stars, _that.language,
            _that.url, _that.description);
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
    TResult? Function(String name, String fullName, int stars, String language,
            String url, String? description)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _RepoInfo() when $default != null:
        return $default(_that.name, _that.fullName, _that.stars, _that.language,
            _that.url, _that.description);
      case _:
        return null;
    }
  }
}

/// @nodoc

class _RepoInfo implements RepoInfo {
  const _RepoInfo(
      {required this.name,
      required this.fullName,
      required this.stars,
      required this.language,
      required this.url,
      this.description});

  /// 仓库短名,如 "flutter"
  @override
  final String name;

  /// 全名,如 "flutter/flutter"
  @override
  final String fullName;

  /// star 数(真实,禁编造 — HANDOFF §6.10)
  @override
  final int stars;

  /// 主语言,如 "Dart"
  @override
  final String language;

  /// 仓库 URL
  @override
  final String url;

  /// 可选描述
  @override
  final String? description;

  /// Create a copy of RepoInfo
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$RepoInfoCopyWith<_RepoInfo> get copyWith =>
      __$RepoInfoCopyWithImpl<_RepoInfo>(this, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _RepoInfo &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.fullName, fullName) ||
                other.fullName == fullName) &&
            (identical(other.stars, stars) || other.stars == stars) &&
            (identical(other.language, language) ||
                other.language == language) &&
            (identical(other.url, url) || other.url == url) &&
            (identical(other.description, description) ||
                other.description == description));
  }

  @override
  int get hashCode => Object.hash(
      runtimeType, name, fullName, stars, language, url, description);

  @override
  String toString() {
    return 'RepoInfo(name: $name, fullName: $fullName, stars: $stars, language: $language, url: $url, description: $description)';
  }
}

/// @nodoc
abstract mixin class _$RepoInfoCopyWith<$Res>
    implements $RepoInfoCopyWith<$Res> {
  factory _$RepoInfoCopyWith(_RepoInfo value, $Res Function(_RepoInfo) _then) =
      __$RepoInfoCopyWithImpl;
  @override
  @useResult
  $Res call(
      {String name,
      String fullName,
      int stars,
      String language,
      String url,
      String? description});
}

/// @nodoc
class __$RepoInfoCopyWithImpl<$Res> implements _$RepoInfoCopyWith<$Res> {
  __$RepoInfoCopyWithImpl(this._self, this._then);

  final _RepoInfo _self;
  final $Res Function(_RepoInfo) _then;

  /// Create a copy of RepoInfo
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? name = null,
    Object? fullName = null,
    Object? stars = null,
    Object? language = null,
    Object? url = null,
    Object? description = freezed,
  }) {
    return _then(_RepoInfo(
      name: null == name
          ? _self.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      fullName: null == fullName
          ? _self.fullName
          : fullName // ignore: cast_nullable_to_non_nullable
              as String,
      stars: null == stars
          ? _self.stars
          : stars // ignore: cast_nullable_to_non_nullable
              as int,
      language: null == language
          ? _self.language
          : language // ignore: cast_nullable_to_non_nullable
              as String,
      url: null == url
          ? _self.url
          : url // ignore: cast_nullable_to_non_nullable
              as String,
      description: freezed == description
          ? _self.description
          : description // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

// dart format on
