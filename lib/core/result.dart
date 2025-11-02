import 'package:bug_reporting_system/exceptions/base_exception.dart';

/// Algebraic data type for success/failure flows that plays nicely with
/// Bloc/Riverpod/Notifier state management.
sealed class Result<T, E extends BaseException> {
  const Result();

  /// Returns `true` when this result contains a value.
  bool get isOk => this is Ok<T, E>;

  /// Returns `true` when this result contains an error.
  bool get isErr => this is Err<T, E>;

  /// Pattern matches on the result, invoking [ok] or [err] accordingly.
  R match<R>({
    required R Function(T value) ok,
    required R Function(E error) err,
  }) {
    final self = this;
    if (self is Ok<T, E>) return ok(self.value);
    return err((self as Err<T, E>).error);
  }

  /// Unwraps the result, throwing if it contains an error.
  T unwrap() {
    final self = this;
    if (self is Ok<T, E>) return self.value;
    throw StateError('Tried to unwrap Err: ${(self as Err<T, E>).error}');
  }

  /// Returns the inner value or [fallback] when this is an error.
  T unwrapOr(T fallback) {
    final self = this;
    if (self is Ok<T, E>) return self.value;
    return fallback;
  }

  /// Returns the inner value or computes one via [f].
  T unwrapOrElse(T Function(E error) f) {
    final self = this;
    if (self is Ok<T, E>) return self.value;
    return f((self as Err<T, E>).error);
  }

  /// Maps the inner value when successful, preserving errors.
  Result<U, E> map<U>(U Function(T value) f) {
    final self = this;
    if (self is Ok<T, E>) return Ok<U, E>(f(self.value));
    return Err<U, E>((self as Err<T, E>).error);
  }

  /// Maps the error type when present, preserving successes.
  Result<T, F> mapErr<F extends BaseException>(F Function(E error) f) {
    final self = this;
    if (self is Err<T, E>) return Err<T, F>(f(self.error));
    return Ok<T, F>((self as Ok<T, E>).value);
  }

  /// Chains another computation only when this result is successful.
  Result<U, E> andThen<U>(Result<U, E> Function(T value) next) {
    final self = this;
    if (self is Ok<T, E>) return next(self.value);
    return Err<U, E>((self as Err<T, E>).error);
  }

  /// Async variant of [andThen] for future-returning pipelines.
  Future<Result<U, E>> andThenAsync<U>(
      Future<Result<U, E>> Function(T value) next) async {
    final self = this;
    if (self is Ok<T, E>) return next(self.value);
    return Err<U, E>((self as Err<T, E>).error);
  }
}

/// Successful result wrapper.
final class Ok<T, E extends BaseException> extends Result<T, E> {
  /// Creates a successful result containing [value].
  const Ok(this.value);

  /// The contained success value.
  final T value;
}

/// Failed result wrapper.
final class Err<T, E extends BaseException> extends Result<T, E> {
  /// Creates a failed result containing [error].
  const Err(this.error);

  /// The contained error instance.
  final E error;
}

/// Async convenience helpers for [Result].
extension ResultX<T, E extends BaseException> on Result<T, E> {
  /// Maps the success value using an async transformer, preserving errors.
  Future<Result<U, E>> mapAsync<U>(Future<U> Function(T value) f) async {
    final self = this;
    if (self is Ok<T, E>) return Ok<U, E>(await f(self.value));
    return Err<U, E>((self as Err<T, E>).error);
  }
}
