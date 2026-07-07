// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'topic.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$Topic {
  /// 话题名(不含 #)
  String get tag;

  /// 真实热度(由 repository 聚合计算,不编造)
  int get heat;

  /// 关联项目数(真实)
  int get projectCount;

  /// 关联动态数(真实)
  int get postCount;

  /// 该话题下所有项目的总点赞数(真实)
  int get totalLikes;

  /// Create a copy of Topic
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $TopicCopyWith<Topic> get copyWith =>
      _$TopicCopyWithImpl<Topic>(this as Topic, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is Topic &&
            (identical(other.tag, tag) || other.tag == tag) &&
            (identical(other.heat, heat) || other.heat == heat) &&
            (identical(other.projectCount, projectCount) ||
                other.projectCount == projectCount) &&
            (identical(other.postCount, postCount) ||
                other.postCount == postCount) &&
            (identical(other.totalLikes, totalLikes) ||
                other.totalLikes == totalLikes));
  }

  @override
  int get hashCode =>
      Object.hash(runtimeType, tag, heat, projectCount, postCount, totalLikes);

  @override
  String toString() {
    return 'Topic(tag: $tag, heat: $heat, projectCount: $projectCount, postCount: $postCount, totalLikes: $totalLikes)';
  }
}

/// @nodoc
abstract mixin class $TopicCopyWith<$Res> {
  factory $TopicCopyWith(Topic value, $Res Function(Topic) _then) =
      _$TopicCopyWithImpl;
  @useResult
  $Res call(
      {String tag, int heat, int projectCount, int postCount, int totalLikes});
}

/// @nodoc
class _$TopicCopyWithImpl<$Res> implements $TopicCopyWith<$Res> {
  _$TopicCopyWithImpl(this._self, this._then);

  final Topic _self;
  final $Res Function(Topic) _then;

  /// Create a copy of Topic
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? tag = null,
    Object? heat = null,
    Object? projectCount = null,
    Object? postCount = null,
    Object? totalLikes = null,
  }) {
    return _then(_self.copyWith(
      tag: null == tag
          ? _self.tag
          : tag // ignore: cast_nullable_to_non_nullable
              as String,
      heat: null == heat
          ? _self.heat
          : heat // ignore: cast_nullable_to_non_nullable
              as int,
      projectCount: null == projectCount
          ? _self.projectCount
          : projectCount // ignore: cast_nullable_to_non_nullable
              as int,
      postCount: null == postCount
          ? _self.postCount
          : postCount // ignore: cast_nullable_to_non_nullable
              as int,
      totalLikes: null == totalLikes
          ? _self.totalLikes
          : totalLikes // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

/// Adds pattern-matching-related methods to [Topic].
extension TopicPatterns on Topic {
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
    TResult Function(_Topic value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _Topic() when $default != null:
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
    TResult Function(_Topic value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _Topic():
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
    TResult? Function(_Topic value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _Topic() when $default != null:
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
    TResult Function(String tag, int heat, int projectCount, int postCount,
            int totalLikes)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _Topic() when $default != null:
        return $default(_that.tag, _that.heat, _that.projectCount,
            _that.postCount, _that.totalLikes);
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
    TResult Function(String tag, int heat, int projectCount, int postCount,
            int totalLikes)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _Topic():
        return $default(_that.tag, _that.heat, _that.projectCount,
            _that.postCount, _that.totalLikes);
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
    TResult? Function(String tag, int heat, int projectCount, int postCount,
            int totalLikes)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _Topic() when $default != null:
        return $default(_that.tag, _that.heat, _that.projectCount,
            _that.postCount, _that.totalLikes);
      case _:
        return null;
    }
  }
}

/// @nodoc

class _Topic implements Topic {
  const _Topic(
      {required this.tag,
      this.heat = 0,
      this.projectCount = 0,
      this.postCount = 0,
      this.totalLikes = 0});

  /// 话题名(不含 #)
  @override
  final String tag;

  /// 真实热度(由 repository 聚合计算,不编造)
  @override
  @JsonKey()
  final int heat;

  /// 关联项目数(真实)
  @override
  @JsonKey()
  final int projectCount;

  /// 关联动态数(真实)
  @override
  @JsonKey()
  final int postCount;

  /// 该话题下所有项目的总点赞数(真实)
  @override
  @JsonKey()
  final int totalLikes;

  /// Create a copy of Topic
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$TopicCopyWith<_Topic> get copyWith =>
      __$TopicCopyWithImpl<_Topic>(this, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _Topic &&
            (identical(other.tag, tag) || other.tag == tag) &&
            (identical(other.heat, heat) || other.heat == heat) &&
            (identical(other.projectCount, projectCount) ||
                other.projectCount == projectCount) &&
            (identical(other.postCount, postCount) ||
                other.postCount == postCount) &&
            (identical(other.totalLikes, totalLikes) ||
                other.totalLikes == totalLikes));
  }

  @override
  int get hashCode =>
      Object.hash(runtimeType, tag, heat, projectCount, postCount, totalLikes);

  @override
  String toString() {
    return 'Topic(tag: $tag, heat: $heat, projectCount: $projectCount, postCount: $postCount, totalLikes: $totalLikes)';
  }
}

/// @nodoc
abstract mixin class _$TopicCopyWith<$Res> implements $TopicCopyWith<$Res> {
  factory _$TopicCopyWith(_Topic value, $Res Function(_Topic) _then) =
      __$TopicCopyWithImpl;
  @override
  @useResult
  $Res call(
      {String tag, int heat, int projectCount, int postCount, int totalLikes});
}

/// @nodoc
class __$TopicCopyWithImpl<$Res> implements _$TopicCopyWith<$Res> {
  __$TopicCopyWithImpl(this._self, this._then);

  final _Topic _self;
  final $Res Function(_Topic) _then;

  /// Create a copy of Topic
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? tag = null,
    Object? heat = null,
    Object? projectCount = null,
    Object? postCount = null,
    Object? totalLikes = null,
  }) {
    return _then(_Topic(
      tag: null == tag
          ? _self.tag
          : tag // ignore: cast_nullable_to_non_nullable
              as String,
      heat: null == heat
          ? _self.heat
          : heat // ignore: cast_nullable_to_non_nullable
              as int,
      projectCount: null == projectCount
          ? _self.projectCount
          : projectCount // ignore: cast_nullable_to_non_nullable
              as int,
      postCount: null == postCount
          ? _self.postCount
          : postCount // ignore: cast_nullable_to_non_nullable
              as int,
      totalLikes: null == totalLikes
          ? _self.totalLikes
          : totalLikes // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

// dart format on
