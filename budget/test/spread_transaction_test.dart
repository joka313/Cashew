import 'package:budget/database/tables.dart';
import 'package:budget/pages/transactionFilters.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/struct/spreadTransaction.dart';
import 'package:budget/widgets/periodCyclePicker.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter_test/flutter_test.dart';

void main() {
  Transaction gym = Transaction(
    transactionPk: "-1",
    name: "Gym",
    amount: -2000000,
    note: "",
    categoryFk: "food",
    walletFk: "0",
    dateCreated: DateTime(2026, 1, 31, 9),
    income: false,
    paid: true,
    skipPaid: false,
  );

  test('splits 2,000,000 VND over 7 months exactly', () {
    List<Transaction> parts =
        spreadTransactionOverMonths(gym, months: 7, decimals: 0, label: "Gym");
    expect(parts.length, 7);
    expect(parts.map((t) => t.amount).toList(), [
      -285715,
      -285715,
      -285714,
      -285714,
      -285714,
      -285714,
      -285714,
    ]);
    expect(parts.fold<double>(0, (sum, t) => sum + t.amount), -2000000);
    expect(parts.first.name, "Gym (1/7)");
    expect(parts.last.name, "Gym (7/7)");
    expect(parts.every((t) => t.paid), true);
  });

  test('one part per month, month end safe', () {
    List<DateTime> dates =
        spreadTransactionOverMonths(gym, months: 4, decimals: 0, label: "Gym")
            .map((t) => t.dateCreated)
            .toList();
    expect(dates, [
      DateTime(2026, 1, 31, 9),
      DateTime(2026, 2, 28, 9),
      DateTime(2026, 3, 31, 9),
      DateTime(2026, 4, 30, 9),
    ]);
  });

  test('decimals and income keep their sign and total', () {
    Transaction income = gym.copyWith(amount: 100, income: true);
    List<Transaction> parts =
        spreadTransactionOverMonths(income, months: 3, decimals: 2, label: "");
    expect(parts.map((t) => t.amount).toList(), [33.34, 33.33, 33.33]);
    expect(parts.first.name, "(1/3)");
  });

  test('one month returns the transaction unchanged', () {
    expect(
        spreadTransactionOverMonths(gym, months: 1, decimals: 0, label: "Gym"),
        [gym]);
  });

  group('database', () {
    late AllWallets allWallets;
    setUp(() async {
      appStateSettings["selectedWalletPk"] = "0";
      appStateSettings["selectedPeriodCycleType"] = CycleType.allTime.index;
      database = FinanceDatabase(NativeDatabase.memory());
      await database.into(database.wallets).insert(WalletsCompanion.insert(
          walletPk: Value("0"),
          name: "Bank",
          order: 0,
          currency: Value("vnd"),
          decimals: Value(0)));
      await database.into(database.categories).insert(
          CategoriesCompanion.insert(
              categoryPk: Value("food"), name: "Food", order: 0));
      TransactionWallet wallet = await database.getWalletInstance("0");
      allWallets = AllWallets(list: [wallet], indexedByPk: {"0": wallet});
    });
    tearDown(() => database.close());

    Future<double> total({DateTimeRange? range}) async =>
        (await database
                .watchTotalWithCountOfWallet(
                  isIncome: null,
                  allWallets: allWallets,
                  forcedDateTimeRange: range,
                  followCustomPeriodCycle: range != null,
                  searchFilters: SearchFilters(walletPks: []),
                )
                .first)
            ?.total ??
        0;

    test('balance drops by the full amount, each month sees one part',
        () async {
      for (Transaction part in spreadTransactionOverMonths(
          gym.copyWith(dateCreated: DateTime(2026, 10, 14, 9)),
          months: 7,
          decimals: 0,
          label: "Gym")) {
        await database.createOrUpdateTransaction(insert: true, part);
      }
      expect(await total(), -2000000);
      expect(
          await total(
              range: DateTimeRange(
                  start: DateTime(2026, 10, 1),
                  end: DateTime(2026, 10, 31, 23, 59))),
          -285715);
      expect(
          await total(
              range: DateTimeRange(
                  start: DateTime(2027, 4, 1),
                  end: DateTime(2027, 4, 30, 23, 59))),
          -285714);
      expect(
          await total(
              range: DateTimeRange(
                  start: DateTime(2027, 5, 1),
                  end: DateTime(2027, 5, 31, 23, 59))),
          0);
    });
  });

  group('spread groups', () {
    setUp(() async {
      database = FinanceDatabase(NativeDatabase.memory());
      await database.into(database.wallets).insert(WalletsCompanion.insert(
          walletPk: Value("0"),
          name: "Bank",
          order: 0,
          currency: Value("vnd"),
          decimals: Value(0)));
      await database.into(database.categories).insert(
          CategoriesCompanion.insert(
              categoryPk: Value("food"), name: "Food", order: 0));
    });
    tearDown(() => database.close());

    Future<List<Transaction>> insertSpread(DateTime start, int months) async {
      List<Transaction> inserted = [];
      for (Transaction part in spreadTransactionOverMonths(
          gym.copyWith(dateCreated: start),
          months: months,
          decimals: 0,
          label: "Gym")) {
        int? rowId =
            await database.createOrUpdateTransaction(insert: true, part);
        inserted.add(await database.getTransactionFromRowId(rowId!));
      }
      return inserted;
    }

    test('parses part names', () {
      SpreadPartName? part = parseSpreadPartName("Gym (3/7)");
      expect([part?.base, part?.index, part?.count], ["Gym", 3, 7]);
      expect(parseSpreadPartName("(1/3)")?.base, "");
      expect(parseSpreadPartName("Gym"), null);
      expect(parseSpreadPartName("Gym (8/7)"), null);
      expect(part!.withIndex(5, base: "Gym Elite"), "Gym Elite (5/7)");
    });

    test('finds every part from any part', () async {
      List<Transaction> parts = await insertSpread(DateTime(2026, 1, 31), 7);
      List<Transaction> group = await findSpreadGroup(parts[4]);
      expect(group.map((t) => t.name).toList(),
          List.generate(7, (i) => "Gym (${i + 1}/7)"));
    });

    test('a renewal with the same title is a separate group', () async {
      List<Transaction> first = await insertSpread(DateTime(2026, 1, 10), 7);
      List<Transaction> renewal = await insertSpread(DateTime(2026, 5, 10), 7);
      List<Transaction> group = await findSpreadGroup(renewal[0]);
      expect(group.map((t) => t.transactionPk).toSet(),
          renewal.map((t) => t.transactionPk).toSet());
      expect((await findSpreadGroup(first[6])).length, 7);
    });

    test('a normal transaction is not a group', () async {
      await insertSpread(DateTime(2026, 1, 10), 3);
      expect(await findSpreadGroup(gym.copyWith(name: "Gym")), isEmpty);
    });
  });
}
