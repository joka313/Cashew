import 'package:budget/database/tables.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/vietqr/vietqr_parser.dart';
import 'package:drift/drift.dart';

// How a VietQR recipient was recorded last time, so scanning the same
// account again fills in the title, category and account.
class VietQrRememberedRecipient {
  VietQrRememberedRecipient({
    required this.title,
    required this.category,
    this.subCategory,
    this.wallet,
  });
  final String title;
  final TransactionCategory category;
  final TransactionCategory? subCategory;
  final TransactionWallet? wallet;
}

// The scan flow puts this note on every transaction it creates
String vietQrNote(VietQrData data) {
  return "QR: " +
      (data.bankName.isNotEmpty ? data.bankName : data.bin) +
      " " +
      data.account;
}

// Null when this account was never paid through the scanner (or its
// category was deleted)
Future<VietQrRememberedRecipient?> findRememberedRecipient(
    VietQrData data) async {
  try {
    String note = vietQrNote(data);
    Transaction? last = await (database.select(database.transactions)
          // Exact note, or the note followed by more text on new lines
          ..where((t) => t.note.equals(note) | t.note.like(note + "\n%"))
          ..orderBy([(t) => OrderingTerm.desc(t.dateCreated)])
          ..limit(1))
        .getSingleOrNull();
    if (last == null) return null;
    TransactionCategory? category =
        await database.getCategoryInstanceOrNull(last.categoryFk);
    if (category == null) return null;
    return VietQrRememberedRecipient(
      title: last.name,
      category: category,
      subCategory: last.subCategoryFk == null
          ? null
          : await database.getCategoryInstanceOrNull(last.subCategoryFk!),
      wallet: await database.getWalletInstanceOrNull(last.walletFk),
    );
  } catch (e) {
    print("VietQR remembered recipient lookup failed: " + e.toString());
    return null;
  }
}
