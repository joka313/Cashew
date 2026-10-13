import 'package:budget/database/tables.dart';
import 'package:budget/struct/upcomingTransactionsFunctions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  DateTime monthly(DateTime date, [int months = 1]) =>
      addRepeatPeriod(date, monthOffset: months);

  test('monthly from the 31st clamps instead of overflowing', () {
    expect(monthly(DateTime(2026, 1, 31, 9, 30)), DateTime(2026, 2, 28, 9, 30));
    expect(monthly(DateTime(2028, 1, 31)), DateTime(2028, 2, 29));
    expect(monthly(DateTime(2026, 3, 31)), DateTime(2026, 4, 30));
  });

  test('last day of month stays on the last day', () {
    DateTime date = DateTime(2026, 1, 31);
    List<DateTime> dates = [];
    for (int i = 0; i < 4; i++) {
      date = monthly(date);
      dates.add(date);
    }
    expect(dates, [
      DateTime(2026, 2, 28),
      DateTime(2026, 3, 31),
      DateTime(2026, 4, 30),
      DateTime(2026, 5, 31),
    ]);
  });

  test('mid-month days are unchanged', () {
    expect(monthly(DateTime(2026, 1, 15)), DateTime(2026, 2, 15));
    expect(monthly(DateTime(2026, 1, 28)), DateTime(2026, 2, 28));
    expect(monthly(DateTime(2026, 2, 28)), DateTime(2026, 3, 31));
    expect(monthly(DateTime(2026, 12, 30), 2), DateTime(2027, 2, 28));
    expect(monthly(DateTime(2026, 11, 15)), DateTime(2026, 12, 15));
    expect(monthly(DateTime(2026, 12, 15)), DateTime(2027, 1, 15));
  });

  test('yearly from Feb 29', () {
    expect(addRepeatPeriod(DateTime(2028, 2, 29), yearOffset: 1),
        DateTime(2029, 2, 28));
    expect(addRepeatPeriod(DateTime(2027, 2, 28), yearOffset: 1),
        DateTime(2028, 2, 29));
  });

  test('daily and weekly are plain day offsets', () {
    expect(addRepeatPeriod(DateTime(2026, 1, 31), dayOffset: 7),
        DateTime(2026, 2, 7));
    expect(addRepeatPeriod(DateTime(2026, 2, 28), dayOffset: 1),
        DateTime(2026, 3, 1));
  });

  test('occurrence count with an end date at the end of a month', () {
    expect(
        countTransactionOccurrences(
          type: TransactionSpecialType.repetitive,
          reoccurrence: BudgetReoccurence.monthly,
          periodLength: 1,
          dateCreated: DateTime(2026, 1, 31),
          endDate: DateTime(2026, 4, 30),
        ),
        4);
    expect(
        countTransactionOccurrences(
          type: TransactionSpecialType.repetitive,
          reoccurrence: BudgetReoccurence.monthly,
          periodLength: 1,
          dateCreated: DateTime(2026, 1, 31),
          endDate: DateTime(2026, 2, 28),
        ),
        2);
  });
}
