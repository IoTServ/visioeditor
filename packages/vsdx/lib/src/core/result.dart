/// A lightweight `Result<T>` (a.k.a. `Either`) for the parsing layer.
///
/// We use this instead of exceptions for **expected** soft-failures (e.g.
/// "this optional section is missing"), keeping the hot path allocation-free.
/// Hard failures still throw [VsdxException].
library;

import 'package:meta/meta.dart';

@immutable
sealed class Result<T> {
  const Result();

  const factory Result.ok(T value) = Ok<T>;
  const factory Result.err(Object error, [StackTrace? stackTrace]) = Err<T>;

  bool get isOk => this is Ok<T>;
  bool get isErr => this is Err<T>;

  /// Unwrap or throw the captured error.
  T unwrap() => switch (this) {
        Ok<T>(:final value) => value,
        Err<T>(:final error, :final stackTrace) =>
          // `Error.throwWithStackTrace` preserves the original stack.
          Error.throwWithStackTrace(error, stackTrace ?? StackTrace.current),
      };

  /// Returns the value or `fallback` when this is [Err].
  T unwrapOr(T fallback) => switch (this) {
        Ok<T>(:final value) => value,
        Err<T>() => fallback,
      };

  /// Map the success value.
  Result<R> map<R>(R Function(T) f) => switch (this) {
        Ok<T>(:final value) => Result<R>.ok(f(value)),
        Err<T>(:final error, :final stackTrace) =>
          Result<R>.err(error, stackTrace),
      };
}

@immutable
final class Ok<T> extends Result<T> {
  const Ok(this.value);
  final T value;

  @override
  bool operator ==(Object other) => other is Ok<T> && other.value == value;
  @override
  int get hashCode => Object.hash(Ok, value);
}

@immutable
final class Err<T> extends Result<T> {
  const Err(this.error, [this.stackTrace]);
  final Object error;
  final StackTrace? stackTrace;

  @override
  bool operator ==(Object other) =>
      other is Err<T> && other.error == error;
  @override
  int get hashCode => Object.hash(Err, error);
}
