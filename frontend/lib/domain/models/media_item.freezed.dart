// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'media_item.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$MediaItem {
  /// 'image' | 'video'
  String get type;

  /// 资源 URL(图片直链 / 视频直链 mp4)
  String get url;

  /// 视频:封面图 URL;图片:可为 null
  String? get poster;

  /// 视频:时长(秒),用于显示 0:30 等;图片:0
  int get durationSec;

  /// 可选描述(alt text,a11y 用)
  String? get alt;

  /// Create a copy of MediaItem
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $MediaItemCopyWith<MediaItem> get copyWith =>
      _$MediaItemCopyWithImpl<MediaItem>(this as MediaItem, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is MediaItem &&
            (identical(other.type, type) || other.type == type) &&
            (identical(other.url, url) || other.url == url) &&
            (identical(other.poster, poster) || other.poster == poster) &&
            (identical(other.durationSec, durationSec) ||
                other.durationSec == durationSec) &&
            (identical(other.alt, alt) || other.alt == alt));
  }

  @override
  int get hashCode =>
      Object.hash(runtimeType, type, url, poster, durationSec, alt);

  @override
  String toString() {
    return 'MediaItem(type: $type, url: $url, poster: $poster, durationSec: $durationSec, alt: $alt)';
  }
}

/// @nodoc
abstract mixin class $MediaItemCopyWith<$Res> {
  factory $MediaItemCopyWith(MediaItem value, $Res Function(MediaItem) _then) =
      _$MediaItemCopyWithImpl;
  @useResult
  $Res call(
      {String type, String url, String? poster, int durationSec, String? alt});
}

/// @nodoc
class _$MediaItemCopyWithImpl<$Res> implements $MediaItemCopyWith<$Res> {
  _$MediaItemCopyWithImpl(this._self, this._then);

  final MediaItem _self;
  final $Res Function(MediaItem) _then;

  /// Create a copy of MediaItem
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? type = null,
    Object? url = null,
    Object? poster = freezed,
    Object? durationSec = null,
    Object? alt = freezed,
  }) {
    return _then(_self.copyWith(
      type: null == type
          ? _self.type
          : type // ignore: cast_nullable_to_non_nullable
              as String,
      url: null == url
          ? _self.url
          : url // ignore: cast_nullable_to_non_nullable
              as String,
      poster: freezed == poster
          ? _self.poster
          : poster // ignore: cast_nullable_to_non_nullable
              as String?,
      durationSec: null == durationSec
          ? _self.durationSec
          : durationSec // ignore: cast_nullable_to_non_nullable
              as int,
      alt: freezed == alt
          ? _self.alt
          : alt // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// Adds pattern-matching-related methods to [MediaItem].
extension MediaItemPatterns on MediaItem {
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
    TResult Function(_MediaItem value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _MediaItem() when $default != null:
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
    TResult Function(_MediaItem value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _MediaItem():
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
    TResult? Function(_MediaItem value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _MediaItem() when $default != null:
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
    TResult Function(String type, String url, String? poster, int durationSec,
            String? alt)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _MediaItem() when $default != null:
        return $default(
            _that.type, _that.url, _that.poster, _that.durationSec, _that.alt);
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
    TResult Function(String type, String url, String? poster, int durationSec,
            String? alt)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _MediaItem():
        return $default(
            _that.type, _that.url, _that.poster, _that.durationSec, _that.alt);
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
    TResult? Function(String type, String url, String? poster, int durationSec,
            String? alt)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _MediaItem() when $default != null:
        return $default(
            _that.type, _that.url, _that.poster, _that.durationSec, _that.alt);
      case _:
        return null;
    }
  }
}

/// @nodoc

class _MediaItem implements MediaItem {
  const _MediaItem(
      {required this.type,
      required this.url,
      this.poster,
      this.durationSec = 0,
      this.alt});

  /// 'image' | 'video'
  @override
  final String type;

  /// 资源 URL(图片直链 / 视频直链 mp4)
  @override
  final String url;

  /// 视频:封面图 URL;图片:可为 null
  @override
  final String? poster;

  /// 视频:时长(秒),用于显示 0:30 等;图片:0
  @override
  @JsonKey()
  final int durationSec;

  /// 可选描述(alt text,a11y 用)
  @override
  final String? alt;

  /// Create a copy of MediaItem
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$MediaItemCopyWith<_MediaItem> get copyWith =>
      __$MediaItemCopyWithImpl<_MediaItem>(this, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _MediaItem &&
            (identical(other.type, type) || other.type == type) &&
            (identical(other.url, url) || other.url == url) &&
            (identical(other.poster, poster) || other.poster == poster) &&
            (identical(other.durationSec, durationSec) ||
                other.durationSec == durationSec) &&
            (identical(other.alt, alt) || other.alt == alt));
  }

  @override
  int get hashCode =>
      Object.hash(runtimeType, type, url, poster, durationSec, alt);

  @override
  String toString() {
    return 'MediaItem(type: $type, url: $url, poster: $poster, durationSec: $durationSec, alt: $alt)';
  }
}

/// @nodoc
abstract mixin class _$MediaItemCopyWith<$Res>
    implements $MediaItemCopyWith<$Res> {
  factory _$MediaItemCopyWith(
          _MediaItem value, $Res Function(_MediaItem) _then) =
      __$MediaItemCopyWithImpl;
  @override
  @useResult
  $Res call(
      {String type, String url, String? poster, int durationSec, String? alt});
}

/// @nodoc
class __$MediaItemCopyWithImpl<$Res> implements _$MediaItemCopyWith<$Res> {
  __$MediaItemCopyWithImpl(this._self, this._then);

  final _MediaItem _self;
  final $Res Function(_MediaItem) _then;

  /// Create a copy of MediaItem
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? type = null,
    Object? url = null,
    Object? poster = freezed,
    Object? durationSec = null,
    Object? alt = freezed,
  }) {
    return _then(_MediaItem(
      type: null == type
          ? _self.type
          : type // ignore: cast_nullable_to_non_nullable
              as String,
      url: null == url
          ? _self.url
          : url // ignore: cast_nullable_to_non_nullable
              as String,
      poster: freezed == poster
          ? _self.poster
          : poster // ignore: cast_nullable_to_non_nullable
              as String?,
      durationSec: null == durationSec
          ? _self.durationSec
          : durationSec // ignore: cast_nullable_to_non_nullable
              as int,
      alt: freezed == alt
          ? _self.alt
          : alt // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

// dart format on
