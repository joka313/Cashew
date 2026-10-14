import 'package:budget/database/tables.dart';
import 'package:budget/pages/transactionFilters.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/periodCyclePicker.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FinanceDatabase db;
  late AllWallets allWallets;
  const double m = 1000000;

  Future<void> addTransaction(String pk, double amount,
      {TransactionSpecialType? type,
      bool paid = true,
      String? objectiveLoanFk}) async {
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          transactionPk: Value(pk),
          name: pk,
          amount: amount,
          note: "",
          categoryFk: "food",
          walletFk: Value("0"),
          income: Value(amount > 0),
          paid: Value(paid),
          type: Value(type),
          objectiveLoanFk: Value(objectiveLoanFk),
        ));
  }

  Future<double> netWorth({required bool includeLoans}) async {
    double cash = (await db
                .watchTotalWithCountOfWallet(
                  isIncome: null,
                  allWallets: allWallets,
                  followCustomPeriodCycle: true,
                  cycleSettingsExtension: "NetWorth",
                  searchFilters: SearchFilters(walletPks: []),
                )
                .first)
            ?.total ??
        0;
    if (!includeLoans) return cash;
    double adjustment = (await db
                .watchNetWorthLoansAdjustment(
                  allWallets: allWallets,
                  walletPks: null,
                  cycleSettingsExtension: "NetWorth",
                )
                .first)
            ?.total ??
        0;
    return cash + adjustment;
  }

  setUp(() async {
    appStateSettings["selectedWalletPk"] = "0";
    appStateSettings["selectedPeriodCycleTypeNetWorth"] =
        CycleType.allTime.index;
    db = FinanceDatabase(NativeDatabase.memory());
    await db.into(db.wallets).insert(WalletsCompanion.insert(
        walletPk: Value("0"), name: "Bank", order: 0, currency: Value("vnd")));
    await db.into(db.categories).insert(CategoriesCompanion.insert(
        categoryPk: Value("food"), name: "Food", order: 0));
    TransactionWallet wallet = await db.getWalletInstance("0");
    allWallets = AllWallets(list: [wallet], indexedByPk: {"0": wallet});

    await addTransaction("salary", 10 * m);
    // One-time loans still outstanding
    await addTransaction("lent", -2 * m, type: TransactionSpecialType.credit);
    await addTransaction("borrowed", 1 * m, type: TransactionSpecialType.debt);
    // A one-time loan already collected (no longer counted anywhere)
    await addTransaction("lent-collected", -3 * m,
        type: TransactionSpecialType.credit, paid: false);
    // Long-term loan given: 5m out, 1m repaid so far
    await db.into(db.objectives).insert(ObjectivesCompanion.insert(
          objectivePk: Value("loan1"),
          name: "Loan to An",
          amount: 0,
          order: 0,
          type: Value(ObjectiveType.loan),
          income: Value(true),
          walletFk: Value("0"),
        ));
    await addTransaction("loan1-initial", -5 * m, objectiveLoanFk: "loan1");
    await addTransaction("loan1-repaid", 1 * m, objectiveLoanFk: "loan1");
  });

  tearDown(() => db.close());

  test('cash basis keeps the old behaviour', () async {
    // 10 - 2 + 1 - 5 + 1
    expect(await netWorth(includeLoans: false), 5 * m);
  });

  test('total assets add lent and subtract borrowed', () async {
    // cash 5 + lent (2 + 4 outstanding) - borrowed 1 = 10
    expect(await netWorth(includeLoans: true), 10 * m);
  });

  test('a long-term loan amount offset counts as owed', () async {
    // Offset entered on a borrowed long-term loan without an initial record
    await db.into(db.objectives).insert(ObjectivesCompanion.insert(
          objectivePk: Value("loan2"),
          name: "Loan from bank",
          amount: 3 * m,
          order: 1,
          type: Value(ObjectiveType.loan),
          income: Value(false),
          walletFk: Value("0"),
        ));
    expect(await netWorth(includeLoans: true), 7 * m);
  });
}
