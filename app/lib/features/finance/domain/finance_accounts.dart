/// Where the money sat — cash, or one of the apps/banks it moves through.
///
/// This is the `account` field of `users/{uid}/transactions/{id}` in
/// `claude/data-model.md`, which has always been in the schema as an optional
/// string. Milestone 1 surfaces it in the form.
///
/// **Why a string key rather than a Dart `enum`** — the same reasoning as
/// `FinanceCategories`, and it matters more here. Bank accounts change: opening
/// a Lulo Bank account should not require editing an enum, rebuilding the APK,
/// reinstalling on the phone, *and* redeploying rules that allowlist the new
/// value. With a string, adding one is a one-line change here, and the rules —
/// which only check `account is string && size <= 40` — never have to move.
///
/// The label is separated from the key for the same reason category labels are:
/// `nubank` sorts and groups predictably, `Nu Bank` is what a person reads.
abstract final class FinanceAccounts {
  /// Display order in the picker. Cash first because it is the most common
  /// entry and the one most often logged in a hurry (NFR-7: under ten seconds,
  /// one-handed).
  static const List<String> all = <String>[
    'cash',
    'nequi',
    'nubank',
    'daviplata',
    'bancolombia',
    'other',
  ];

  /// What a form starts on, and what pre-Milestone-1 documents are shown as
  /// when they have no `account` field at all.
  static const String fallback = 'cash';

  static const Map<String, String> _labels = <String, String>{
    'cash': 'Cash',
    'nequi': 'Nequi',
    'nubank': 'Nu Bank',
    'daviplata': 'Daviplata',
    'bancolombia': 'Bancolombia',
    'other': 'Other',
  };

  /// `nubank` → `Nu Bank`.
  ///
  /// Falls back to capitalising the key, so a value typed straight into the
  /// Firestore console — or one added to [all] and not to [_labels] — still
  /// renders as something readable instead of blank.
  static String label(String? account) {
    if (account == null || account.isEmpty) return _labels[fallback]!;
    return _labels[account] ?? account[0].toUpperCase() + account.substring(1);
  }

  /// Whether a stored value is one this build knows how to offer in the picker.
  ///
  /// A document written by a future version — or edited in the console — can
  /// hold an account this build has never heard of. The form asks this before
  /// selecting it in a dropdown, because handing `DropdownButton` a value that
  /// is not among its items throws.
  static bool isKnown(String? account) =>
      account != null && all.contains(account);
}
