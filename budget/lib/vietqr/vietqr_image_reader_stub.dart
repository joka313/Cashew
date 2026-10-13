import 'package:budget/vietqr/vietqr_image_reader.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

Future<String> readQrFromImagePath(String path) async {
  MobileScannerController controller = MobileScannerController(
    autoStart: false,
    formats: const [BarcodeFormat.qrCode],
  );
  try {
    BarcodeCapture? capture = await controller.analyzeImage(path);
    for (Barcode barcode in capture?.barcodes ?? []) {
      String? raw = barcode.rawValue;
      if (raw != null && raw.isNotEmpty) return raw;
    }
  } finally {
    controller.dispose();
  }
  throw VietQrImageException(
      'Không tìm thấy mã QR trong ảnh. Thử cắt sát mã QR rồi chọn lại.');
}

// Only text is supported outside of the web
Future<String> readQrFromClipboard() async {
  ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
  String text = data?.text ?? "";
  if (text.trim().isEmpty) {
    throw VietQrImageException('Clipboard không có chuỗi QR.');
  }
  return text;
}
