import 'dart:math';

import 'package:budget/colors.dart';
import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart';
import 'package:budget/pages/addTransactionPage.dart';
import 'package:budget/vietqr/vietqr_image_reader.dart';
import 'package:budget/vietqr/vietqr_memory.dart';
import 'package:budget/vietqr/vietqr_parser.dart';
import 'package:budget/vietqr/vietqr_paste_target.dart';
import 'package:budget/vietqr/vietqr_transfer_sheet.dart';
import 'package:budget/widgets/button.dart';
import 'package:budget/widgets/framework/pageFramework.dart';
import 'package:budget/widgets/navigationFramework.dart';
import 'package:budget/widgets/openBottomSheet.dart';
import 'package:budget/widgets/openPopup.dart';
import 'package:budget/widgets/textInput.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

// Scan a VietQR, add it as an expense, then offer to transfer via the bank app
Future openVietQrScanFlow(BuildContext context) async {
  dynamic result = await pushRoute(context, VietQrScanPage());
  if (result is! VietQrData) return;
  VietQrData data = result;

  String title = data.note.isNotEmpty ? data.note : data.name;
  // A recipient paid before: reuse its title, category and account and go
  // straight to the amount
  VietQrRememberedRecipient? remembered = await findRememberedRecipient(data);
  if (remembered != null && remembered.title.trim().isNotEmpty) {
    title = remembered.title;
  }
  Transaction? savedTransaction;
  if (!context.mounted) return;
  await pushRoute(
    context,
    AddTransactionPage(
      routesToPopAfterDelete: RoutesToPopAfterDelete.None,
      selectedIncome: false,
      selectedAmount: data.amount,
      selectedTitle: title.isEmpty ? null : title,
      selectedCategory: remembered?.category,
      selectedSubCategory: remembered?.subCategory,
      selectedWallet: remembered?.wallet,
      skipTitlePrompt: remembered != null,
      selectedNotes: vietQrNote(data),
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
  bool readingQr = false;
  bool showPasteTarget = false;
  String? errorMessage;
  // Camera errors must not overwrite a message from Pick photo / Paste
  // right away, the camera keeps reporting any non-VietQR code it sees
  DateTime? manualMessageTime;

  @override
  void dispose() {
    scannerController.dispose();
    pasteController.dispose();
    super.dispose();
  }

  void showError(String message, {required bool fromCamera}) {
    if (fromCamera &&
        manualMessageTime != null &&
        DateTime.now().difference(manualMessageTime!) < Duration(seconds: 6)) {
      return;
    }
    if (fromCamera == false) manualMessageTime = DateTime.now();
    setState(() {
      errorMessage = message;
    });
  }

  // Returns true when the QR was accepted and the page is closing
  bool handleQrString(String raw, {bool fromCamera = false}) {
    if (handled) return false;
    VietQrData data;
    try {
      data = parseVietQr(raw);
    } on VietQrFormatException catch (e) {
      showError(e.message, fromCamera: fromCamera);
      return false;
    }
    if (data.crcValid == false) {
      showError("Mã QR bị lỗi (sai mã kiểm tra CRC). Hãy quét lại.",
          fromCamera: fromCamera);
      return false;
    }
    if (data.account.isEmpty) {
      showError("Mã QR không có số tài khoản người nhận.",
          fromCamera: fromCamera);
      return false;
    }
    handled = true;
    scannerController.stop();
    popRoute(context, data);
    return true;
  }

  // The reader is called synchronously so clipboard access keeps the tap gesture
  Future readQrFrom(Future<String?> Function() reader) async {
    if (readingQr || handled) return;
    setState(() {
      readingQr = true;
      errorMessage = null;
    });
    try {
      String? raw = await reader();
      if (raw != null && mounted) handleQrString(raw);
    } on VietQrImageException catch (e) {
      if (mounted && e.clipboardEmpty) {
        // iOS hides copied photos from the clipboard API, a real paste works
        setState(() => showPasteTarget = true);
        showError('Chạm giữ vào ô bên dưới rồi chọn "Dán".', fromCamera: false);
      } else if (mounted) {
        showError(e.message, fromCamera: false);
      }
    } catch (e) {
      if (mounted) {
        showError("Không đọc được mã QR: " + e.toString(), fromCamera: false);
      }
    } finally {
      if (mounted) setState(() => readingQr = false);
    }
  }

  // Returns null when the user cancels the picker
  Future<String?> pickImageAndReadQr() async {
    XFile? file = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file == null) return null;
    return await readQrFromImagePath(file.path);
  }

  String cameraErrorMessage(MobileScannerException error) {
    if (error.errorCode == MobileScannerErrorCode.permissionDenied) {
      return "Chưa được cấp quyền camera. Hãy cho phép camera cho trang này (Cài đặt > Safari > Camera) rồi thử lại.";
    }
    String details = error.errorDetails?.message ?? "";
    return "Không mở được camera." +
        (details.isEmpty ? "" : " (" + details + ")");
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
                      if (handleQrString(raw, fromCamera: true)) return;
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
            text: readingQr
                ? "Đang đọc mã QR..."
                : errorMessage ?? "Đưa mã VietQR chuyển khoản vào khung hình.",
            fontSize: 15,
            maxLines: 5,
            textAlign: TextAlign.center,
            textColor: errorMessage != null
                ? Theme.of(context).colorScheme.error
                : getColor(context, "textLight"),
          ),
        ),
        SizedBox(height: 15),
        Padding(
          padding: const EdgeInsetsDirectional.symmetric(horizontal: 18),
          child: Row(
            children: [
              Expanded(
                child: Button(
                  label: "Chọn ảnh",
                  icon: Icons.photo_library_rounded,
                  expandedLayout: true,
                  disabled: readingQr,
                  onTap: () {
                    readQrFrom(pickImageAndReadQr);
                  },
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: Button(
                  label: "Dán",
                  icon: Icons.content_paste_rounded,
                  expandedLayout: true,
                  disabled: readingQr,
                  onTap: () {
                    readQrFrom(readQrFromClipboard);
                  },
                ),
              ),
            ],
          ),
        ),
        if (showPasteTarget) ...[
          SizedBox(height: 15),
          Padding(
            padding: const EdgeInsetsDirectional.symmetric(horizontal: 18),
            child: buildVietQrPasteTarget(
              placeholder: 'Chạm giữ vào đây rồi chọn "Dán"',
              textColor: getColor(context, "textLight"),
              borderColor: Theme.of(context).colorScheme.primary,
              onPaste: (Future<String> result) {
                readQrFrom(() => result);
              },
            ),
          ),
        ],
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
