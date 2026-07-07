// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'io_block.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$IoBlock {
  /// 输入内容(prompt / 配置 / 命令)
  String get input;

  /// 输出效果(AI 生成的结果文本)
  String get output;

  /// 可选标题,如 "GPT-4o" / "Claude 3.5" / "Midjourney v6"
  String? get model;

  /// 可选语言标签(若输入是代码)
  String? get lang;

  /// Create a copy of IoBlock
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $IoBlockCopyWith<IoBlock> get copyWith =>
      _$IoBlockCopyWithImpl<IoBlock>(this as IoBlock, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is IoBlock &&
            (identical(other.input, input) || other.input == input) &&
            (identical(other.output, output) || other.output == output) &&
            (identical(other.model, model) || other.model == model) &&
            (identical(other.lang, lang) || other.lang == lang));
  }

  @override
  int get hashCode => Object.hash(runtimeType, input, output, model, lang);

  @override
  String toString() {
    return 'IoBlock(input: $input, output: $output, model: $model, lang: $lang)';
  }
}

/// @nodoc
abstract mixin class $IoBlockCopyWith<$Res> {
  factory $IoBlockCopyWith(IoBlock value, $Res Function(IoBlock) _then) =
      _$IoBlockCopyWithImpl;
  @useResult
  $Res call({String input, String output, String? model, String? lang});
}

/// @nodoc
class _$IoBlockCopyWithImpl<$Res> implements $IoBlockCopyWith<$Res> {
  _$IoBlockCopyWithImpl(this._self, this._then);

  final IoBlock _self;
  final $Res Function(IoBlock) _then;

  /// Create a copy of IoBlock
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? input = null,
    Object? output = null,
    Object? model = freezed,
    Object? lang = freezed,
  }) {
    return _then(_self.copyWith(
      input: null == input
          ? _self.input
          : input // ignore: cast_nullable_to_non_nullable
              as String,
      output: null == output
          ? _self.output
          : output // ignore: cast_nullable_to_non_nullable
              as String,
      model: freezed == model
          ? _self.model
          : model // ignore: cast_nullable_to_non_nullable
              as String?,
      lang: freezed == lang
          ? _self.lang
          : lang // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// Adds pattern-matching-related methods to [IoBlock].
extension IoBlockPatterns on IoBlock {
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
    TResult Function(_IoBlock value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _IoBlock() when $default != null:
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
    TResult Function(_IoBlock value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _IoBlock():
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
    TResult? Function(_IoBlock value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _IoBlock() when $default != null:
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
    TResult Function(String input, String output, String? model, String? lang)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _IoBlock() when $default != null:
        return $default(_that.input, _that.output, _that.model, _that.lang);
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
    TResult Function(String input, String output, String? model, String? lang)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _IoBlock():
        return $default(_that.input, _that.output, _that.model, _that.lang);
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
    TResult? Function(String input, String output, String? model, String? lang)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _IoBlock() when $default != null:
        return $default(_that.input, _that.output, _that.model, _that.lang);
      case _:
        return null;
    }
  }
}

/// @nodoc

class _IoBlock implements IoBlock {
  const _IoBlock(
      {required this.input, required this.output, this.model, this.lang});

  /// 输入内容(prompt / 配置 / 命令)
  @override
  final String input;

  /// 输出效果(AI 生成的结果文本)
  @override
  final String output;

  /// 可选标题,如 "GPT-4o" / "Claude 3.5" / "Midjourney v6"
  @override
  final String? model;

  /// 可选语言标签(若输入是代码)
  @override
  final String? lang;

  /// Create a copy of IoBlock
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$IoBlockCopyWith<_IoBlock> get copyWith =>
      __$IoBlockCopyWithImpl<_IoBlock>(this, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _IoBlock &&
            (identical(other.input, input) || other.input == input) &&
            (identical(other.output, output) || other.output == output) &&
            (identical(other.model, model) || other.model == model) &&
            (identical(other.lang, lang) || other.lang == lang));
  }

  @override
  int get hashCode => Object.hash(runtimeType, input, output, model, lang);

  @override
  String toString() {
    return 'IoBlock(input: $input, output: $output, model: $model, lang: $lang)';
  }
}

/// @nodoc
abstract mixin class _$IoBlockCopyWith<$Res> implements $IoBlockCopyWith<$Res> {
  factory _$IoBlockCopyWith(_IoBlock value, $Res Function(_IoBlock) _then) =
      __$IoBlockCopyWithImpl;
  @override
  @useResult
  $Res call({String input, String output, String? model, String? lang});
}

/// @nodoc
class __$IoBlockCopyWithImpl<$Res> implements _$IoBlockCopyWith<$Res> {
  __$IoBlockCopyWithImpl(this._self, this._then);

  final _IoBlock _self;
  final $Res Function(_IoBlock) _then;

  /// Create a copy of IoBlock
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? input = null,
    Object? output = null,
    Object? model = freezed,
    Object? lang = freezed,
  }) {
    return _then(_IoBlock(
      input: null == input
          ? _self.input
          : input // ignore: cast_nullable_to_non_nullable
              as String,
      output: null == output
          ? _self.output
          : output // ignore: cast_nullable_to_non_nullable
              as String,
      model: freezed == model
          ? _self.model
          : model // ignore: cast_nullable_to_non_nullable
              as String?,
      lang: freezed == lang
          ? _self.lang
          : lang // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

// dart format on
