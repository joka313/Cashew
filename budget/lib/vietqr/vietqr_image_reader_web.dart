import 'dart:async';
import 'dart:collection';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math';

import 'package:budget/vietqr/vietqr_image_reader.dart';

// Same script and id that mobile_scanner uses, so the library is loaded once
const String _zxingScriptUrl = 'https://unpkg.com/@zxing/library@0.19.1';
const String _zxingScriptId = 'mobile-scanner-barcode-reader';
const int _maxImageSide = 1600;

JSObject get _document => globalContext.getProperty<JSObject>('document'.toJS);

Future<void> _loadZXing() async {
  if (globalContext.has('ZXing')) return;
  JSObject? existing = _document.callMethod<JSObject?>(
      'getElementById'.toJS, _zxingScriptId.toJS);
  Completer<void> completer = Completer();
  if (existing == null) {
    JSObject script =
        _document.callMethod<JSObject>('createElement'.toJS, 'script'.toJS);
    script.setProperty('id'.toJS, _zxingScriptId.toJS);
    script.setProperty('crossOrigin'.toJS, 'anonymous'.toJS);
    script.setProperty('src'.toJS, _zxingScriptUrl.toJS);
    script.setProperty(
        'onload'.toJS,
        ((JSAny _) {
          if (!completer.isCompleted) completer.complete();
        }).toJS);
    script.setProperty(
        'onerror'.toJS,
        ((JSAny _) {
          if (!completer.isCompleted) {
            completer.completeError(VietQrImageException(
                'Không tải được thư viện đọc QR. Kiểm tra kết nối mạng.'));
          }
        }).toJS);
    _document.getProperty<JSObject>('head'.toJS).callMethod(
        'appendChild'.toJS, script);
    await completer.future;
  } else {
    // The script tag exists but may still be loading
    for (int i = 0; i < 100 && !globalContext.has('ZXing'); i++) {
      await Future.delayed(Duration(milliseconds: 100));
    }
  }
  if (!globalContext.has('ZXing')) {
    throw VietQrImageException('Không tải được thư viện đọc QR.');
  }
}

Future<JSObject> _loadImage(String url) {
  Completer<JSObject> completer = Completer();
  JSObject image = globalContext
      .getProperty<JSFunction>('Image'.toJS)
      .callAsConstructor<JSObject>();
  image.setProperty(
      'onload'.toJS,
      ((JSAny _) {
        if (!completer.isCompleted) completer.complete(image);
      }).toJS);
  image.setProperty(
      'onerror'.toJS,
      ((JSAny _) {
        if (!completer.isCompleted) {
          completer.completeError(VietQrImageException('Không mở được ảnh.'));
        }
      }).toJS);
  image.setProperty('src'.toJS, url.toJS);
  return completer.future;
}

// Large photos are slow and less reliable to decode, scale them down first
Future<String> _downscaledDataUrl(String url) async {
  JSObject image = await _loadImage(url);
  int width = image.getProperty<JSNumber>('naturalWidth'.toJS).toDartInt;
  int height = image.getProperty<JSNumber>('naturalHeight'.toJS).toDartInt;
  if (width == 0 || height == 0) return url;
  double scale = min(1.0, _maxImageSide / max(width, height));
  if (scale >= 1.0) return url;
  JSObject canvas =
      _document.callMethod<JSObject>('createElement'.toJS, 'canvas'.toJS);
  canvas.setProperty('width'.toJS, (width * scale).round().toJS);
  canvas.setProperty('height'.toJS, (height * scale).round().toJS);
  JSObject ctx = canvas.callMethod<JSObject>('getContext'.toJS, '2d'.toJS);
  ctx.callMethodVarArgs('drawImage'.toJS, [
    image,
    0.toJS,
    0.toJS,
    (width * scale).round().toJS,
    (height * scale).round().toJS,
  ]);
  return canvas
      .callMethod<JSString>('toDataURL'.toJS, 'image/png'.toJS)
      .toDart;
}

Future<String?> _decodeUrl(String url) async {
  JSObject zxing = globalContext.getProperty<JSObject>('ZXing'.toJS);
  JSObject reader = zxing
      .getProperty<JSFunction>('BrowserQRCodeReader'.toJS)
      .callAsConstructor<JSObject>();
  try {
    JSObject result = await reader
        .callMethod<JSPromise<JSObject>>('decodeFromImageUrl'.toJS, url.toJS)
        .toDart;
    return result.callMethod<JSString>('getText'.toJS).toDart;
  } catch (e) {
    // ZXing rejects with NotFoundException when there is no QR in the image
    return null;
  } finally {
    reader.callMethod('reset'.toJS);
  }
}

Future<String> _decodeImageUrl(String url) async {
  await _loadZXing();
  String? text = await _decodeUrl(await _downscaledDataUrl(url));
  // A small QR in a big photo can be lost when scaled down, retry full size
  text ??= await _decodeUrl(url);
  if (text == null || text.isEmpty) {
    throw VietQrImageException(
        'Không tìm thấy mã QR trong ảnh. Thử cắt sát mã QR rồi chọn lại.');
  }
  return text;
}

Future<String> readQrFromImagePath(String path) {
  // On web, image_picker returns a blob: URL as the path
  return _decodeImageUrl(path);
}

Future<String> readQrFromClipboard() async {
  JSObject navigator = globalContext.getProperty<JSObject>('navigator'.toJS);
  JSObject? clipboard = navigator.getProperty<JSObject?>('clipboard'.toJS);
  if (clipboard == null) {
    throw VietQrImageException('Trình duyệt không cho phép đọc clipboard.');
  }

  // Must be called right away inside the tap, before any await
  if (clipboard.has('read')) {
    JSPromise<JSArray<JSObject>> readPromise =
        clipboard.callMethod<JSPromise<JSArray<JSObject>>>('read'.toJS);
    List<JSObject> items;
    try {
      items = (await readPromise.toDart).toDart;
    } catch (e) {
      throw VietQrImageException(
          'Không đọc được clipboard. Hãy bấm "Dán" khi iOS hỏi.');
    }
    for (JSObject item in items) {
      List<String> types = item
          .getProperty<JSArray<JSString>>('types'.toJS)
          .toDart
          .map((type) => type.toDart)
          .toList();
      String? imageType =
          types.where((type) => type.startsWith('image/')).firstOrNull;
      if (imageType != null) {
        JSObject blob = await item
            .callMethod<JSPromise<JSObject>>('getType'.toJS, imageType.toJS)
            .toDart;
        JSObject urlApi = globalContext.getProperty<JSObject>('URL'.toJS);
        String url = urlApi
            .callMethod<JSString>('createObjectURL'.toJS, blob)
            .toDart;
        try {
          return await _decodeImageUrl(url);
        } finally {
          urlApi.callMethod('revokeObjectURL'.toJS, url.toJS);
        }
      }
      if (types.contains('text/plain')) {
        JSObject blob = await item
            .callMethod<JSPromise<JSObject>>('getType'.toJS, 'text/plain'.toJS)
            .toDart;
        String text =
            (await blob.callMethod<JSPromise<JSString>>('text'.toJS).toDart)
                .toDart;
        if (text.trim().isNotEmpty) return text;
      }
    }
    throw VietQrImageException('Clipboard không có ảnh QR hay chuỗi QR.');
  }

  if (clipboard.has('readText')) {
    String text = (await clipboard
            .callMethod<JSPromise<JSString>>('readText'.toJS)
            .toDart)
        .toDart;
    if (text.trim().isNotEmpty) return text;
  }
  throw VietQrImageException('Clipboard không có ảnh QR hay chuỗi QR.');
}
