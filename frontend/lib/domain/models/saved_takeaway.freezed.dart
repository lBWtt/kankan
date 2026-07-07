// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'saved_takeaway.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$SavedTakeaway {
  /// 唯一 ID(由 projectId + actionIndex 拼成,保证可去重)
  String get id;

  /// 来源项目 ID
  String get projectId;

  /// 来源项目标题(冗余存储,避免每次 join)
  String get projectTitle;

  /// 来源项目领域(用于按领域筛选,可选)
  String get domain;

  /// 分类:'text' | 'file' | 'link'
  String get kind;

  /// 内容本体:
  ///   - kind == 'text'  → 复制的文本
  ///   - kind == 'file'  → 文件下载链接
  ///   - kind == 'link'  → 跳转的 URL
  String get source;

  /// 可选对象名(从 TakeAction.label / GoAction.label 来)
  String? get label;

  /// 拿走时间(毫秒)
  int get savedAtMs;

  /// Create a copy of SavedTakeaway
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $SavedTakeawayCopyWith<SavedTakeaway> get copyWith =>
      _$SavedTakeawayCopyWithImpl<SavedTakeaway>(
          this as SavedTakeaway, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is SavedTakeaway &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.projectId, projectId) ||
                other.projectId == projectId) &&
            (identical(other.projectTitle, projectTitle) ||
                other.projectTitle == projectTitle) &&
            (identical(other.domain, domain) || other.domain == domain) &&
            (identical(other.kind, kind) || other.kind == kind) &&
            (identical(other.source, source) || other.source == source) &&
            (identical(other.label, label) || other.label == label) &&
            (identical(other.savedAtMs, savedAtMs) ||
                other.savedAtMs == savedAtMs));
  }

  @override
  int get hashCode => Object.hash(runtimeType, id, projectId, projectTitle,
      domain, kind, source, label, savedAtMs);

  @override
  String toString() {
    return 'SavedTakeaway(id: $id, projectId: $projectId, projectTitle: $projectTitle, domain: $domain, kind: $kind, source: $source, label: $label, savedAtMs: $savedAtMs)';
  }
}

/// @nodoc
abstract mixin class $SavedTakeawayCopyWith<$Res> {
  factory $SavedTakeawayCopyWith(
          SavedTakeaway value, $Res Function(SavedTakeaway) _then) =
      _$SavedTakeawayCopyWithImpl;
  @useResult
  $Res call(
      {String id,
      String projectId,
      String projectTitle,
      String domain,
      String kind,
      String source,
      String? label,
      int savedAtMs});
}

/// @nodoc
class _$SavedTakeawayCopyWithImpl<$Res>
    implements $SavedTakeawayCopyWith<$Res> {
  _$SavedTakeawayCopyWithImpl(this._self, this._then);

  final SavedTakeaway _self;
  final $Res Function(SavedTakeaway) _then;

  /// Create a copy of SavedTakeaway
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? projectId = null,
    Object? projectTitle = null,
    Object? domain = null,
    Object? kind = null,
    Object? source = null,
    Object? label = freezed,
    Object? savedAtMs = null,
  }) {
    return _then(_self.copyWith(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      projectId: null == projectId
          ? _self.projectId
          : projectId // ignore: cast_nullable_to_non_nullable
              as String,
      projectTitle: null == projectTitle
          ? _self.projectTitle
          : projectTitle // ignore: cast_nullable_to_non_nullable
              as String,
      domain: null == domain
          ? _self.domain
          : domain // ignore: cast_nullable_to_non_nullable
              as String,
      kind: null == kind
          ? _self.kind
          : kind // ignore: cast_nullable_to_non_nullable
              as String,
      source: null == source
          ? _self.source
          : source // ignore: cast_nullable_to_non_nullable
              as String,
      label: freezed == label
          ? _self.label
          : label // ignore: cast_nullable_to_non_nullable
              as String?,
      savedAtMs: null == savedAtMs
          ? _self.savedAtMs
          : savedAtMs // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

/// Adds pattern-matching-related methods to [SavedTakeaway].
extension SavedTakeawayPatterns on SavedTakeaway {
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
    TResult Function(_SavedTakeaway value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _SavedTakeaway() when $default != null:
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
    TResult Function(_SavedTakeaway value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _SavedTakeaway():
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
    TResult? Function(_SavedTakeaway value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _SavedTakeaway() when $default != null:
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
            String projectId,
            String projectTitle,
            String domain,
            String kind,
            String source,
            String? label,
            int savedAtMs)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _SavedTakeaway() when $default != null:
        return $default(
            _that.id,
            _that.projectId,
            _that.projectTitle,
            _that.domain,
            _that.kind,
            _that.source,
            _that.label,
            _that.savedAtMs);
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
            String projectId,
            String projectTitle,
            String domain,
            String kind,
            String source,
            String? label,
            int savedAtMs)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _SavedTakeaway():
        return $default(
            _that.id,
            _that.projectId,
            _that.projectTitle,
            _that.domain,
            _that.kind,
            _that.source,
            _that.label,
            _that.savedAtMs);
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
            String projectId,
            String projectTitle,
            String domain,
            String kind,
            String source,
            String? label,
            int savedAtMs)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _SavedTakeaway() when $default != null:
        return $default(
            _that.id,
            _that.projectId,
            _that.projectTitle,
            _that.domain,
            _that.kind,
            _that.source,
            _that.label,
            _that.savedAtMs);
      case _:
        return null;
    }
  }
}

/// @nodoc

class _SavedTakeaway implements SavedTakeaway {
  const _SavedTakeaway(
      {required this.id,
      required this.projectId,
      required this.projectTitle,
      required this.domain,
      required this.kind,
      required this.source,
      this.label,
      required this.savedAtMs});

  /// 唯一 ID(由 projectId + actionIndex 拼成,保证可去重)
  @override
  final String id;

  /// 来源项目 ID
  @override
  final String projectId;

  /// 来源项目标题(冗余存储,避免每次 join)
  @override
  final String projectTitle;

  /// 来源项目领域(用于按领域筛选,可选)
  @override
  final String domain;

  /// 分类:'text' | 'file' | 'link'
  @override
  final String kind;

  /// 内容本体:
  ///   - kind == 'text'  → 复制的文本
  ///   - kind == 'file'  → 文件下载链接
  ///   - kind == 'link'  → 跳转的 URL
  @override
  final String source;

  /// 可选对象名(从 TakeAction.label / GoAction.label 来)
  @override
  final String? label;

  /// 拿走时间(毫秒)
  @override
  final int savedAtMs;

  /// Create a copy of SavedTakeaway
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$SavedTakeawayCopyWith<_SavedTakeaway> get copyWith =>
      __$SavedTakeawayCopyWithImpl<_SavedTakeaway>(this, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _SavedTakeaway &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.projectId, projectId) ||
                other.projectId == projectId) &&
            (identical(other.projectTitle, projectTitle) ||
                other.projectTitle == projectTitle) &&
            (identical(other.domain, domain) || other.domain == domain) &&
            (identical(other.kind, kind) || other.kind == kind) &&
            (identical(other.source, source) || other.source == source) &&
            (identical(other.label, label) || other.label == label) &&
            (identical(other.savedAtMs, savedAtMs) ||
                other.savedAtMs == savedAtMs));
  }

  @override
  int get hashCode => Object.hash(runtimeType, id, projectId, projectTitle,
      domain, kind, source, label, savedAtMs);

  @override
  String toString() {
    return 'SavedTakeaway(id: $id, projectId: $projectId, projectTitle: $projectTitle, domain: $domain, kind: $kind, source: $source, label: $label, savedAtMs: $savedAtMs)';
  }
}

/// @nodoc
abstract mixin class _$SavedTakeawayCopyWith<$Res>
    implements $SavedTakeawayCopyWith<$Res> {
  factory _$SavedTakeawayCopyWith(
          _SavedTakeaway value, $Res Function(_SavedTakeaway) _then) =
      __$SavedTakeawayCopyWithImpl;
  @override
  @useResult
  $Res call(
      {String id,
      String projectId,
      String projectTitle,
      String domain,
      String kind,
      String source,
      String? label,
      int savedAtMs});
}

/// @nodoc
class __$SavedTakeawayCopyWithImpl<$Res>
    implements _$SavedTakeawayCopyWith<$Res> {
  __$SavedTakeawayCopyWithImpl(this._self, this._then);

  final _SavedTakeaway _self;
  final $Res Function(_SavedTakeaway) _then;

  /// Create a copy of SavedTakeaway
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? id = null,
    Object? projectId = null,
    Object? projectTitle = null,
    Object? domain = null,
    Object? kind = null,
    Object? source = null,
    Object? label = freezed,
    Object? savedAtMs = null,
  }) {
    return _then(_SavedTakeaway(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      projectId: null == projectId
          ? _self.projectId
          : projectId // ignore: cast_nullable_to_non_nullable
              as String,
      projectTitle: null == projectTitle
          ? _self.projectTitle
          : projectTitle // ignore: cast_nullable_to_non_nullable
              as String,
      domain: null == domain
          ? _self.domain
          : domain // ignore: cast_nullable_to_non_nullable
              as String,
      kind: null == kind
          ? _self.kind
          : kind // ignore: cast_nullable_to_non_nullable
              as String,
      source: null == source
          ? _self.source
          : source // ignore: cast_nullable_to_non_nullable
              as String,
      label: freezed == label
          ? _self.label
          : label // ignore: cast_nullable_to_non_nullable
              as String?,
      savedAtMs: null == savedAtMs
          ? _self.savedAtMs
          : savedAtMs // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

// dart format on
