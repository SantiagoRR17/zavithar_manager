# ADR 0009 — Money and date formatting

**Status:** Accepted
**Date:** 2026-08-25
**Context:** Milestone 1, the first screen that displays stored data.

## Context

Nothing in `claude/requirements.md` or `claude/data-model.md` ever pinned a
currency — the schema says `amount` is a number and stops there, which is
correct for storage and useless for a list row that has to render it. Milestone
1 forced the question.

## Decision

**The currency is the Colombian peso (COP), formatted `$12.500`.**

All money and date formatting lives in `app/lib/core/format/money.dart`, and
nowhere else — the same rule `app_colors.dart` applies to hex literals, for the
same reason. Changing currency is changing two constants in that file.

Three specifics that are less obvious than they look:

### `NumberFormat.currency(locale: 'es_CO')` is not used

It produces `12.500 $` — CLDR places the symbol *after* the number for `es_CO`.
That is defensible formal Spanish typography and it is not how anyone in
Colombia writes a price. The app takes the locale's **separators** (`.` for
thousands) via `NumberFormat('#,##0', 'es_CO')` and prepends the symbol itself.

### Amounts display with no decimal places

Everyday COP is whole pesos; `,00` on every row is noise. This is a *display*
decision — `amount` remains a `num` in Firestore and nothing rounds on write.

`Money.tryParse` therefore strips every non-digit, so `12.500`, `12,500` and
`$ 12.500` all parse to 12500. In `es_CO` a dot is a thousands separator, so
`12.500` genuinely means twelve thousand five hundred, not twelve and a half —
there is no ambiguity to preserve, and rejecting a user's input over a
separator they typed out of habit would be hostile.

### Dates are formatted in `en_US`, explicitly

The UI copy is English, so Spanish month names next to an English "Yesterday"
would read as a bug. But the locale string matters mechanically, not just
editorially:

- `DateFormat` knows **only `en_US`** until `initializeDateFormatting()` is
  called. A bare `'en'` throws `LocaleDataException` at the first format call —
  this was caught by a unit test, not on device.
- Omitting the locale is worse than getting it wrong: `DateFormat` then follows
  `Intl.defaultLocale`, so the code would pass in tests and throw on a phone set
  to Spanish.

`NumberFormat` has no such problem — its symbol data ships inside the `intl`
package, which is why the currency side needs no initialisation.

## Also decided here: the model is `FinanceTransaction`

`cloud_firestore` already exports a class called `Transaction` — its
batched-write handle. A model named `Transaction` would collide in every file
importing both, and papering over that with import prefixes across the codebase
is worse than one clear name.

## Consequences

- New dependency: `intl` (0.20.3). First non-Firebase, non-state package in the
  project; it is a Dart-team package with no platform channels, so it carries no
  Windows risk (cf. ADR 0006).
- Anything rendering money must call `Money.format`. A raw
  `'\$$amount'` anywhere is a bug, and will format differently from every other
  row on the screen.
- A future multi-currency feature — not in scope for v1 — would replace the
  file-level constants with a per-transaction currency field. Nothing outside
  `money.dart` would need to know.
