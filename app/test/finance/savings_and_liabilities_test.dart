// Unit tests for the savings and liability models.
//
// Same principle as `finance_transaction_test.dart`: no Firebase, no emulator,
// no initialisation — these are plain Dart objects, so the parts with logic
// worth testing run in milliseconds.
//
// The progress getters get the most attention here, because they are the only
// arithmetic in the feature and every one of them has an edge case that draws
// something visibly wrong when it is missed.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zavithar_manager/features/finance/domain/liability.dart';
import 'package:zavithar_manager/features/finance/domain/savings_goal.dart';

void main() {
  group('SavingsGoal', () {
    SavingsGoal goal({
      num target = 100000,
      num current = 25000,
      DateTime? deadline,
    }) {
      return SavingsGoal(
        id: 'g1',
        name: 'New laptop',
        targetAmount: target,
        currentAmount: current,
        deadline: deadline,
      );
    }

    test('progress is the fraction saved', () {
      expect(goal(current: 25000).progress, 0.25);
      expect(goal(current: 0).progress, 0);
      expect(goal(current: 100000).progress, 1);
    });

    test('progress clamps so an over-saved goal cannot overdraw the bar', () {
      // A LinearProgressIndicator given 1.4 paints past its own track.
      expect(goal(current: 140000).progress, 1);
    });

    test('progress survives a zero target rather than dividing by zero', () {
      // Not reachable through the form or the rules, but reachable through the
      // console — and NaN would render as a blank bar with no clue why.
      expect(goal(target: 0, current: 500).progress, 0);
    });

    test('remaining never goes negative', () {
      expect(goal(current: 25000).remaining, 75000);
      expect(goal(current: 140000).remaining, 0);
    });

    test('isComplete is true at exactly the target', () {
      expect(goal(current: 99999).isComplete, isFalse);
      expect(goal(current: 100000).isComplete, isTrue);
      expect(goal(current: 100001).isComplete, isTrue);
    });

    test('an absent deadline is omitted, not written as null', () {
      // A present-but-null key still counts as present to the rules' allowlist.
      expect(goal().toMap().containsKey(SavingsGoal.fieldDeadline), isFalse);
      expect(
        goal(deadline: DateTime(2026, 12, 1))
            .toMap()
            .containsKey(SavingsGoal.fieldDeadline),
        isTrue,
      );
    });

    test('a deadline can be cleared, which copyWith alone cannot express', () {
      final SavingsGoal withDeadline = goal(deadline: DateTime(2026, 12, 1));

      // Null means "unchanged" to copyWith, so this leaves it in place...
      expect(withDeadline.copyWith().deadline, isNotNull);
      // ...and only the explicit flag removes it.
      expect(withDeadline.copyWith(clearDeadline: true).deadline, isNull);
    });

    test('survives a round trip through the Firestore map', () {
      final DateTime deadline = DateTime(2026, 12, 1);
      final SavingsGoal original = goal(deadline: deadline);
      final SavingsGoal restored = SavingsGoal.fromMap(
        original.id,
        original.toMap(),
      );

      expect(restored.name, original.name);
      expect(restored.targetAmount, original.targetAmount);
      expect(restored.currentAmount, original.currentAmount);
      expect(restored.deadline, deadline);
    });

    test('never writes its own audit timestamps', () {
      final Map<String, Object?> map = goal().toMap();
      expect(map.containsKey(SavingsGoal.fieldCreatedAt), isFalse);
      expect(map.containsKey(SavingsGoal.fieldUpdatedAt), isFalse);
    });

    test('tolerates a document written by a broken client', () {
      final SavingsGoal parsed = SavingsGoal.fromMap(
        'g',
        const <String, Object?>{},
      );
      expect(parsed.name, 'Untitled goal');
      expect(parsed.targetAmount, 0);
      expect(parsed.progress, 0);
    });
  });

  group('Liability', () {
    Liability debt({
      num original = 100000,
      num remaining = 40000,
      num? interestRate,
      DateTime? dueDate,
      num? minimumPayment,
    }) {
      return Liability(
        id: 'l1',
        name: 'Car loan',
        type: 'loan',
        originalAmount: original,
        remainingAmount: remaining,
        interestRate: interestRate,
        dueDate: dueDate,
        minimumPayment: minimumPayment,
      );
    }

    test('progress counts the debt down, not up', () {
      // 60% repaid means a 60% full bar. A bar that fills as the debt grows
      // would be defensible and miserable to look at.
      expect(debt(remaining: 40000).progress, closeTo(0.6, 1e-9));
      expect(debt(remaining: 100000).progress, 0);
      expect(debt(remaining: 0).progress, 1);
    });

    test('progress clamps when a debt has grown past what was borrowed', () {
      // Interest and late fees make this real, and the model records it rather
      // than refusing it — but the bar still cannot paint a negative.
      expect(debt(remaining: 130000).progress, 0);
    });

    test('amountPaid never goes negative', () {
      expect(debt(remaining: 40000).amountPaid, 60000);
      expect(debt(remaining: 130000).amountPaid, 0);
    });

    test('isPaidOff covers an overpayment as well as an exact one', () {
      expect(debt(remaining: 1).isPaidOff, isFalse);
      expect(debt(remaining: 0).isPaidOff, isTrue);
      expect(debt(remaining: -50).isPaidOff, isTrue);
    });

    test('every optional field is omitted when absent', () {
      final Map<String, Object?> map = debt().toMap();
      expect(map.containsKey(Liability.fieldInterestRate), isFalse);
      expect(map.containsKey(Liability.fieldDueDate), isFalse);
      expect(map.containsKey(Liability.fieldMinimumPayment), isFalse);
    });

    test('each optional field has its own clear flag', () {
      final Liability full = debt(
        interestRate: 12,
        minimumPayment: 5000,
        dueDate: DateTime(2026, 9, 1),
      );

      expect(full.copyWith().interestRate, 12);
      expect(full.copyWith(clearInterestRate: true).interestRate, isNull);
      expect(full.copyWith(clearMinimumPayment: true).minimumPayment, isNull);
      expect(full.copyWith(clearDueDate: true).dueDate, isNull);
      // Clearing one must not disturb the others.
      expect(full.copyWith(clearDueDate: true).interestRate, 12);
    });

    test('survives a round trip through the Firestore map', () {
      final DateTime due = DateTime(2026, 9, 1);
      final Liability original = debt(
        interestRate: 12.5,
        dueDate: due,
        minimumPayment: 5000,
      );
      final Liability restored = Liability.fromMap(
        original.id,
        original.toMap(),
      );

      expect(restored.name, original.name);
      expect(restored.type, original.type);
      expect(restored.originalAmount, original.originalAmount);
      expect(restored.remainingAmount, original.remainingAmount);
      expect(restored.interestRate, 12.5);
      expect(restored.minimumPayment, 5000);
      expect(restored.dueDate, due);
    });

    test('reads a Timestamp back as a DateTime', () {
      final DateTime due = DateTime(2026, 9, 1);
      final Liability parsed = Liability.fromMap('l', <String, Object?>{
        Liability.fieldName: 'Card',
        Liability.fieldType: 'credit card',
        Liability.fieldOriginalAmount: 100,
        Liability.fieldRemainingAmount: 50,
        Liability.fieldDueDate: Timestamp.fromDate(due),
      });

      expect(parsed.dueDate, due);
    });

    test('tolerates a document written by a broken client', () {
      final Liability parsed = Liability.fromMap(
        'l',
        const <String, Object?>{},
      );
      expect(parsed.name, 'Untitled');
      expect(parsed.type, LiabilityTypes.fallback);
      expect(parsed.progress, 0);
    });
  });

  group('LiabilityTypes', () {
    test('every type fits the 40-character limit the rules enforce', () {
      for (final String type in LiabilityTypes.all) {
        expect(type.length, lessThanOrEqualTo(40));
        expect(type, type.toLowerCase());
      }
    });

    test('the fallback is one of the offered types', () {
      // Otherwise a document with a missing type would parse into a value the
      // dropdown cannot display, and selecting it would throw.
      expect(LiabilityTypes.all, contains(LiabilityTypes.fallback));
    });

    test('an unknown type is not offered to the dropdown', () {
      expect(LiabilityTypes.isKnown('student loan'), isFalse);
      expect(LiabilityTypes.isKnown(null), isFalse);
      expect(LiabilityTypes.isKnown('mortgage'), isTrue);
    });

    test('labels capitalise without mangling multi-word types', () {
      expect(LiabilityTypes.label('credit card'), 'Credit card');
      expect(LiabilityTypes.label('loan'), 'Loan');
    });
  });
}
