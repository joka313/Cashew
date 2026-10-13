import 'package:budget/colors.dart';
import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart';
import 'package:budget/vietqr/vietqr_parser.dart';
import 'package:budget/widgets/button.dart';
import 'package:budget/widgets/framework/popupFramework.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/link.dart';

// Shown only after the transaction from the QR was saved to the database
class VietQrTransferSheet extends StatelessWidget {
  const VietQrTransferSheet({
    required this.data,
    required this.transaction,
    super.key,
  });

  final VietQrData data;
  final Transaction transaction;

  @override
  Widget build(BuildContext context) {
    AllWallets allWallets = Provider.of<AllWallets>(context, listen: false);
    double amount = transaction.amount.abs();
    String? link = buildVietQrTransferLink(
      account: data.account,
      bankCode: data.bankCode,
      amount: amount,
      note: data.note.isNotEmpty ? data.note : transaction.name,
      name: data.name,
      appUrl: Uri.base.toString(),
    );

    return PopupFramework(
      title: "Đã lưu giao dịch",
      subtitle: convertToMoney(allWallets, amount,
              currencyKey:
                  allWallets.indexedByPk[transaction.walletFk]?.currency) +
          " → " +
          (data.bankName.isNotEmpty ? data.bankName : data.bin) +
          " " +
          data.account,
      child: Column(
        children: [
          if (link == null)
            Padding(
              padding: const EdgeInsetsDirectional.only(bottom: 15),
              child: TextFont(
                text: "Không tạo được liên kết chuyển khoản (thiếu số tiền).",
                fontSize: 15,
                maxLines: 3,
                textAlign: TextAlign.center,
                textColor: getColor(context, "textLight"),
              ),
            )
          else
            // A real <a target="_blank"> on web, tapped directly by the user
            Link(
              uri: Uri.parse(link),
              target: LinkTarget.blank,
              builder: (context, followLink) {
                return Button(
                  label: "Chuyển khoản qua " + vietQrBankAppName,
                  expandedLayout: true,
                  onTap: () {
                    followLink?.call();
                  },
                );
              },
            ),
          SizedBox(height: 10),
          Button(
            label: "Đóng",
            expandedLayout: true,
            color: Theme.of(context).colorScheme.secondaryContainer,
            textColor: Theme.of(context).colorScheme.onSecondaryContainer,
            onTap: () {
              popRoute(context);
            },
          ),
        ],
      ),
    );
  }
}
