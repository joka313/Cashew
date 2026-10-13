import 'dart:math';

import 'package:budget/colors.dart';
import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart';
import 'package:budget/pages/addTransactionPage.dart';
import 'package:budget/vietqr/vietqr_parser.dart';
import 'package:budget/vietqr/vietqr_transfer_sheet.dart';
import 'package:budget/widgets/button.dart';
import 'package:budget/widgets/framework/pageFramework.dart';
import 'package:budget/widgets/navigationFramework.dart';
import 'package:budget/widgets/openBottomSheet.dart';
import 'package:budget/widgets/openPopup.dart';
import 'package:budget/widgets/textInput.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

// Scan a VietQR, add it as an expense, then offer to transfer via the bank app
Future openVietQrScanFlow(BuildContext context) async {
  dynamic result = await pushRoute(context, VietQrScanPage());
  if (result is! VietQrData) return;
  VietQrData data = result;

  String title = data.note.isNotEmpty ? data.note : data.name;
  Transaction? savedTransaction;
  await pushRoute(
    context,
    AddTransactionPage(
      routesToPopAfterDelete: RoutesToPopAfterDelete.None,
      selectedIncome: false,
      selectedAmount: data.amount,
      selectedTitle: title.isEmpty ? null : title,
      selectedNotes: "QR: " +
          (data.bankName.isNotEmpty ? data.bankName : data.bin) +
          " " +
          data.account,
      onTransactionAdded: (Transaction transaction) {
        savedTransaction = transaction;
      },
    ),
  );

  // The transaction is already in the database at this point
  if (savedTransaction == null) return;
  BuildContext? sheetContext =
      context.mounted ? context : navigatorKey.currentContext;
  if (sheetContext == null) return;
  await openBottomSheet(
    sheetContext,
    VietQrTransferSheet(data: data, transaction: savedTransaction!),
  );
}

class VietQrScanPage extends StatefulWidget {
  const VietQrScanPage({super.key});

  @override
  State<VietQrScanPage> createState() => _VietQrScanPageState();
}

class _VietQrScanPageState extends State<VietQrScanPage> {
  final MobileScannerController scannerController = MobileScannerController(
    facing: CameraFacing.back,
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  final TextEditingController pasteController = TextEditingController();
  bool handled = false;
  bool cameraFailed = false;
  String? errorMessage;

  @override
  void dispose() {
    scannerController.dispose();
    pasteController.dispose();
    super.dispose();
  }

  // Returns true when the QR was accepted and the page is closing
  bool handleQrString(String raw) {
    if (handled) return false;
    VietQrData data;
    try {
      data = parseVietQr(raw);
    } on VietQrFormatException catch (e) {
      setState(() {
        errorMessage = e.message;
      });
      return false;
    }
    if (data.crcValid == false) {
      setState(() {
        errorMessage = "Mã QR bị lỗi (sai mã kiểm tra CRC). Hãy quét lại.";
      });
      return false;
    }
    if (data.account.isEmpty) {
      setState(() {
        errorMessage = "Mã QR không có số tài khoản người nhận.";
      });
      return false;
    }
    handled = true;
    scannerController.stop();
    popRoute(context, data);
    return true;
  }

  String cameraErrorMessage(MobileScannerException error) {
    if (error.errorCode == MobileScannerErrorCode.permissionDenied) {
      return "Chưa được cấp quyền camera. Hãy cho phép camera cho trang này (Cài đặt > Safari > Camera) rồi thử lại.";
    }
    String details = error.errorDetails?.message ?? "";
    return "Không mở được camera." + (details.isEmpty ? "" : " (" + details + ")");
  }

  @override
  Widget build(BuildContext context) {
    double scannerSize = min(MediaQuery.sizeOf(context).width - 36, 420);
    return PageFramework(
      title: "Quét VietQR",
      dragDownToDismiss: true,
      listWidgets: [
        Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: SizedBox(
              width: scannerSize,
              height: scannerSize,
              child: MobileScanner(
                controller: scannerController,
                onDetect: (BarcodeCapture capture) {
                  for (Barcode barcode in capture.barcodes) {
                    String? raw = barcode.rawValue;
                    if (raw != null && raw.isNotEmpty) {
                      if (handleQrString(raw)) return;
                    }
                  }
                },
                errorBuilder: (context, error, child) {
                  if (cameraFailed == false) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) setState(() => cameraFailed = true);
                    });
                  }
                  return Container(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    padding: EdgeInsetsDirectional.all(20),
                    alignment: Alignment.center,
                    child: TextFont(
                      text: cameraErrorMessage(error),
                      fontSize: 16,
                      maxLines: 6,
                      textAlign: TextAlign.center,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        SizedBox(height: 15),
        Padding(
          padding: const EdgeInsetsDirectional.symmetric(horizontal: 18),
          child: TextFont(
            text: errorMessage ?? "Đưa mã VietQR chuyển khoản vào khung hình.",
            fontSize: 15,
            maxLines: 5,
            textAlign: TextAlign.center,
            textColor: errorMessage != null
                ? Theme.of(context).colorScheme.error
                : getColor(context, "textLight"),
          ),
        ),
        if (cameraFailed) ...[
          SizedBox(height: 20),
          TextInput(
            labelText: "Dán chuỗi QR (000201...)",
            controller: pasteController,
            minLines: 2,
            maxLines: 5,
            autocorrect: false,
            keyboardType: TextInputType.multiline,
            padding: const EdgeInsetsDirectional.symmetric(horizontal: 18),
          ),
          SizedBox(height: 12),
          Padding(
            padding: const EdgeInsetsDirectional.symmetric(horizontal: 18),
            child: Button(
              label: "Giải mã chuỗi QR",
              expandedLayout: true,
              onTap: () {
                handleQrString(pasteController.text);
              },
            ),
          ),
        ],
        SizedBox(height: 30),
      ],
    );
  }
}
