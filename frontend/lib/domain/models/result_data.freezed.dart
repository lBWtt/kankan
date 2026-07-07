// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'result_data.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$ResultData {
  /// 媒体列表(视频优先排序由 detail 渲染器负责)
  List<MediaItem> get media;

  /// GitHub 等仓库卡(可选)
  RepoInfo? get repo;

  /// 输入→输出效果(可选)
  IoBlock? get io;

  /// 纯心得正文(media/repo/io 皆空时显示)
  String? get text;

  /// Create a copy of ResultData
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $ResultDataCopyWith<ResultData> get copyWith =>
      _$ResultDataCopyWithImpl<ResultData>(this as ResultData, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is ResultData &&
            const DeepCollectionEquality().equals(other.media, media) &&
            (identical(other.repo, repo) || other.repo == repo) &&
            (identical(other.io, io) || other.io == io) &&
            (identical(other.text, text) || other.text == text));
  }

  @override
  int get hashCode => Object.hash(
      runtimeType, const DeepCollectionEquality().hash(media), repo, io, text);

  @override
  String toString() {
    return 'ResultData(media: $media, repo: $repo, io: $io, text: $text)';
  }
}

/// @nodoc
abstract mixin class $ResultDataCopyWith<$Res> {
  factory $ResultDataCopyWith(
          ResultData value, $Res Function(ResultData) _then) =
      _$ResultDataCopyWithImpl;
  @useResult
  $Res call({List<MediaItem> media, RepoInfo? repo, IoBlock? io, String? text});

  $RepoInfoCopyWith<$Res>? get repo;
  $IoBlockCopyWith<$Res>? get io;
}

/// @nodoc
class _$ResultDataCopyWithImpl<$Res> implements $ResultDataCopyWith<$Res> {
  _$ResultDataCopyWithImpl(this._self, this._then);

  final ResultData _self;
  final $Res Function(ResultData) _then;

  /// Create a copy of ResultData
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? media = null,
    Object? repo = freezed,
    Object? io = freezed,
    Object? text = freezed,
  }) {
    return _then(_self.copyWith(
      media: null == media
          ? _self.media
          : media // ignore: cast_nullable_to_non_nullable
              as List<MediaItem>,
      repo: freezed == repo
          ? _self.repo
          : repo // ignore: cast_nullable_to_non_nullable
              as RepoInfo?,
      io: freezed == io
          ? _self.io
          : io // ignore: cast_nullable_to_non_nullable
              as IoBlock?,
      text: freezed == text
          ? _self.text
          : text // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }

  /// Create a copy of ResultData
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $RepoInfoCopyWith<$Res>? get repo {
    if (_self.repo == null) {
      return null;
    }

    return $RepoInfoCopyWith<$Res>(_self.repo!, (value) {
      return _then(_self.copyWith(repo: value));
    });
  }

  /// Create a copy of ResultData
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $IoBlockCopyWith<$Res>? get io {
    if (_self.io == null) {
      return null;
    }

    return $IoBlockCopyWith<$Res>(_self.io!, (value) {
      return _then(_self.copyWith(io: value));
    });
  }
}

/// Adds pattern-matching-related methods to [ResultData].
extension ResultDataPatterns on ResultData {
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
    TResult Function(_ResultData value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _ResultData() when $default != null:
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
    TResult Function(_ResultData value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _ResultData():
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
    TResult? Function(_ResultData value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _ResultData() when $default != null:
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
            List<MediaItem> media, RepoInfo? repo, IoBlock? io, String? text)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _ResultData() when $default != null:
        return $default(_that.media, _that.repo, _that.io, _that.text);
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
            List<MediaItem> media, RepoInfo? repo, IoBlock? io, String? text)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _ResultData():
        return $default(_that.media, _that.repo, _that.io, _that.text);
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
            List<MediaItem> media, RepoInfo? repo, IoBlock? io, String? text)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _ResultData() when $default != null:
        return $default(_that.media, _that.repo, _that.io, _that.text);
      case _:
        return null;
    }
  }
}

/// @nodoc

class _ResultData implements ResultData {
  const _ResultData(
      {final List<MediaItem> media = const [], this.repo, this.io, this.text})
      : _media = media;

  /// 媒体列表(视频优先排序由 detail 渲染器负责)
  final List<MediaItem> _media;

  /// 媒体列表(视频优先排序由 detail 渲染器负责)
  @override
  @JsonKey()
  List<MediaItem> get media {
    if (_media is EqualUnmodifiableListView) return _media;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_media);
  }

  /// GitHub 等仓库卡(可选)
  @override
  final RepoInfo? repo;

  /// 输入→输出效果(可选)
  @override
  final IoBlock? io;

  /// 纯心得正文(media/repo/io 皆空时显示)
  @override
  final String? text;

  /// Create a copy of ResultData
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$ResultDataCopyWith<_ResultData> get copyWith =>
      __$ResultDataCopyWithImpl<_ResultData>(this, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _ResultData &&
            const DeepCollectionEquality().equals(other._media, _media) &&
            (identical(other.repo, repo) || other.repo == repo) &&
            (identical(other.io, io) || other.io == io) &&
            (identical(other.text, text) || other.text == text));
  }

  @override
  int get hashCode => Object.hash(
      runtimeType, const DeepCollectionEquality().hash(_media), repo, io, text);

  @override
  String toString() {
    return 'ResultData(media: $media, repo: $repo, io: $io, text: $text)';
  }
}

/// @nodoc
abstract mixin class _$ResultDataCopyWith<$Res>
    implements $ResultDataCopyWith<$Res> {
  factory _$ResultDataCopyWith(
          _ResultData value, $Res Function(_ResultData) _then) =
      __$ResultDataCopyWithImpl;
  @override
  @useResult
  $Res call({List<MediaItem> media, RepoInfo? repo, IoBlock? io, String? text});

  @override
  $RepoInfoCopyWith<$Res>? get repo;
  @override
  $IoBlockCopyWith<$Res>? get io;
}

/// @nodoc
class __$ResultDataCopyWithImpl<$Res> implements _$ResultDataCopyWith<$Res> {
  __$ResultDataCopyWithImpl(this._self, this._then);

  final _ResultData _self;
  final $Res Function(_ResultData) _then;

  /// Create a copy of ResultData
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? media = null,
    Object? repo = freezed,
    Object? io = freezed,
    Object? text = freezed,
  }) {
    return _then(_ResultData(
      media: null == media
          ? _self._media
          : media // ignore: cast_nullable_to_non_nullable
              as List<MediaItem>,
      repo: freezed == repo
          ? _self.repo
          : repo // ignore: cast_nullable_to_non_nullable
              as RepoInfo?,
      io: freezed == io
          ? _self.io
          : io // ignore: cast_nullable_to_non_nullable
              as IoBlock?,
      text: freezed == text
          ? _self.text
          : text // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }

  /// Create a copy of ResultData
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $RepoInfoCopyWith<$Res>? get repo {
    if (_self.repo == null) {
      return null;
    }

    return $RepoInfoCopyWith<$Res>(_self.repo!, (value) {
      return _then(_self.copyWith(repo: value));
    });
  }

  /// Create a copy of ResultData
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $IoBlockCopyWith<$Res>? get io {
    if (_self.io == null) {
      return null;
    }

    return $IoBlockCopyWith<$Res>(_self.io!, (value) {
      return _then(_self.copyWith(io: value));
    });
  }
}

// dart format on
