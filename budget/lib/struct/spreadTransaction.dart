import 'dart:math';

import 'package:budget/database/tables.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/upcomingTransactionsFunctions.dart';
import 'package:drift/drift.dart' hide Column;

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

// A part of a spread payment, from its name "Title (i/N)"
class SpreadPartName {
  SpreadPartName(this.base, this.index, this.count);
  final String base;
  final int index;
  final int count;

  String withIndex(int index, {String? base}) {
    String name = (base ?? this.base).trim();
    return (name.isEmpty ? "" : name + " ") + "($index/$count)";
  }
}

final RegExp _spreadPartPattern = RegExp(r'^(?:(.*) )?\((\d+)/(\d+)\)$');

SpreadPartName? parseSpreadPartName(String name) {
  RegExpMatch? match = _spreadPartPattern.firstMatch(name.trim());
  if (match == null) return null;
  int index = int.parse(match.group(2)!);
  int count = int.parse(match.group(3)!);
  if (count < 2 || index < 1 || index > count) return null;
  return SpreadPartName(match.group(1) ?? "", index, count);
}

int _monthNumber(DateTime date) => date.year * 12 + date.month;

// All parts of the spread payment this transaction belongs to, itself
// included, ordered by part number. Empty when it is not a spread part.
// Parts are matched by title, part count, category and account, and their
// month distance must equal their part number distance, so a later renewal
// with the same title is a separate group.
Future<List<Transaction>> findSpreadGroup(Transaction transaction) async {
  SpreadPartName? part = parseSpreadPartName(transaction.name);
  if (part == null) return [];
  List<Transaction> candidates = await (database.select(database.transactions)
        ..where((t) =>
            t.categoryFk.equals(transaction.categoryFk) &
            t.walletFk.equals(transaction.walletFk) &
            t.name.like("%(%/" + part.count.toString() + ")")))
      .get();
  Map<int, Transaction> byIndex = {};
  for (Transaction candidate in candidates) {
    SpreadPartName? other = parseSpreadPartName(candidate.name);
    if (other == null ||
        other.count != part.count ||
        other.base.trim() != part.base.trim()) continue;
    int monthGap = _monthNumber(candidate.dateCreated) -
        _monthNumber(transaction.dateCreated);
    if (monthGap != other.index - part.index) continue;
    byIndex[other.index] = candidate;
  }
  if (byIndex.length < 2) return [];
  return (byIndex.keys.toList()..sort()).map((i) => byIndex[i]!).toList();
}
