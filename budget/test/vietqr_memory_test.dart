import 'package:budget/database/tables.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/vietqr/vietqr_memory.dart';
import 'package:budget/vietqr/vietqr_parser.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  VietQrData qr(String account) => VietQrData(
        bin: "970432",
        bankCode: "vpb",
        bankName: "VPBank",
        account: account,
        amount: null,
        note: "",
        name: "",
        crcValid: true,
      );

  Future<void> add(String pk, String name, String note, String category,
      DateTime date) async {
    await database.into(database.transactions).insert(
        TransactionsCompanion.insert(
            transactionPk: Value(pk),
            name: name,
            amount: -50000,
            note: note,
            categoryFk: category,
            walletFk: Value("0"),
            dateCreated: Value(date)));
  }

  setUp(() async {
    database = FinanceDatabase(NativeDatabase.memory());
    await database.into(database.wallets).insert(WalletsCompanion.insert(
        walletPk: Value("0"), name: "Bank", order: 0, currency: Value("vnd")));
    for (String pk in ["food", "gym"]) {
      await database.into(database.categories).insert(
          CategoriesCompanion.insert(
              categoryPk: Value(pk), name: pk, order: 0));
    }
  });
  tearDown(() => database.close());

  test('uses the latest transaction to the same account', () async {
    await add(
        "a", "Cafe", "QR: VPBank 0357479509", "food", DateTime(2026, 9, 1));
    await add("b", "Gym tháng 10", "QR: VPBank 0357479509", "gym",
        DateTime(2026, 10, 1));
    VietQrRememberedRecipient? r =
        await findRememberedRecipient(qr("0357479509"));
    expect(r?.title, "Gym tháng 10");
    expect(r?.category.categoryPk, "gym");
    expect(r?.wallet?.walletPk, "0");
  });

  test('a longer account number is a different recipient', () async {
    await add(
        "a", "Cafe", "QR: VPBank 03574795091", "food", DateTime(2026, 9, 1));
    expect(await findRememberedRecipient(qr("0357479509")), null);
  });

  test('notes with extra lines still match', () async {
    await add("a", "Cafe", "QR: VPBank 0357479509\nmang về", "food",
        DateTime(2026, 9, 1));
    expect((await findRememberedRecipient(qr("0357479509")))?.title, "Cafe");
  });

  test('unknown account or deleted category gives nothing', () async {
    await add(
        "a", "Cafe", "QR: VPBank 0357479509", "deleted", DateTime(2026, 9, 1));
    expect(await findRememberedRecipient(qr("0357479509")), null);
    expect(await findRememberedRecipient(qr("1111")), null);
  });
}
