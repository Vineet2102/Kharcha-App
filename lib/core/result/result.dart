/// A minimal Ok/Err result type. Repositories return `Result<T, Failure>`
/// and never throw across the repository boundary (spec §9.7).
sealed class Result<T, F> {
  const Result();

  const factory Result.ok(T value) = Ok<T, F>;
  const factory Result.err(F failure) = Err<T, F>;

  bool get isOk => this is Ok<T, F>;
  bool get isErr => this is Err<T, F>;

  T? get valueOrNull => switch (this) {
    Ok<T, F>(:final value) => value,
    Err<T, F>() => null,
  };

  F? get failureOrNull => switch (this) {
    Ok<T, F>() => null,
    Err<T, F>(:final failure) => failure,
  };

  R fold<R>(R Function(T value) onOk, R Function(F failure) onErr) =>
      switch (this) {
        Ok<T, F>(:final value) => onOk(value),
        Err<T, F>(:final failure) => onErr(failure),
      };

  Result<R, F> map<R>(R Function(T value) transform) => switch (this) {
    Ok<T, F>(:final value) => Result.ok(transform(value)),
    Err<T, F>(:final failure) => Result.err(failure),
  };
}

final class Ok<T, F> extends Result<T, F> {
  const Ok(this.value);
  final T value;
}

final class Err<T, F> extends Result<T, F> {
  const Err(this.failure);
  final F failure;
}
