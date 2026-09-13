import 'package:flutter/foundation.dart';

/// A Firestore error that is safe and useful to show in the UI.
///
/// Every repository translates `FirebaseException` into this before it can
/// reach a widget, so presentation code never has to know Firestore's error
/// codes — the data-layer counterpart to `AuthFailure`.
///
/// Lives in `core/` rather than in a feature because three features now throw
/// it. It began as `DataFailure` inside `TransactionsRepository`; when todos
/// needed it too the choice was either a `todos -> finance` import that means
/// nothing, or this.
@immutable
class DataFailure implements Exception {
  const DataFailure(this.message);

  final String message;

  @override
  String toString() => message;
}
