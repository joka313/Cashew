// Reads a QR string from an image file or the clipboard.
// Web decodes images with the ZXing library that mobile_scanner loads,
// other platforms use mobile_scanner's analyzeImage.
export 'vietqr_image_reader_stub.dart'
    if (dart.library.js_interop) 'vietqr_image_reader_web.dart';

class VietQrImageException implements Exception {
  VietQrImageException(this.message);
  final String message;

  @override
  String toString() => message;
}
