import 'dart:math';

import 'package:budget/database/tables.dart';
import 'package:budget/struct/upcomingTransactionsFunctions.dart';

// Records one payment (e.g. a 7 month gym membership) as equal monthly parts.
// Every part is paid, so the account balance drops by the full amount right
// away, while monthly spending and budgets only count one part per month.
// The amount is split in the wallet's smallest unit and the remainder goes to
// the first months, so the parts always add up to the original amount.
List<Transaction> spreadTransactionOverMonths(
  Transaction transaction, {
  required int months,
  required int decimals,
  required String label,
}) {
  if (months <= 1) return [transaction];
  double factor = pow(10, decimals).toDouble();
  int totalUnits = (transaction.amount.abs() * factor).round();
  int baseUnits = totalUnits ~/ months;
  int remainder = totalUnits - baseUnits * months;
  double sign = transaction.amount < 0 ? -1 : 1;
  String name = label.trim();
  return [
    for (int i = 0; i < months; i++)
      transaction.copyWith(
        amount: sign * (baseUnits + (i < remainder ? 1 : 0)) / factor,
        dateCreated: addRepeatPeriod(transaction.dateCreated, monthOffset: i),
        name: (name.isEmpty ? "" : name + " ") + "(${i + 1}/$months)",
      ),
  ];
}
