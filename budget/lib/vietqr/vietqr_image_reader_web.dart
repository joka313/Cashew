import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math';

import 'package:budget/vietqr/vietqr_image_reader.dart';

// Same script and id that mobile_scanner uses, so the library is loaded once
const String _zxingScriptUrl = 'https://unpkg.com/@zxing/library@0.19.1';
const String _zxingScriptId = 'mobile-scanner-barcode-reader';
const int _maxImageSide = 1600;
const int _maxRetryImageSide = 4000;

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
    _document
        .getProperty<JSObject>('head'.toJS)
        .callMethod('appendChild'.toJS, script);
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

JSObject _newZXing(String name, [JSAny? arg]) {
  JSFunction constructor = globalContext
      .getProperty<JSObject>('ZXing'.toJS)
      .getProperty<JSFunction>(name.toJS);
  return arg == null
      ? constructor.callAsConstructor<JSObject>()
      : constructor.callAsConstructor<JSObject>(arg);
}

JSObject _drawOnCanvas(JSObject image, int width, int height, int maxSide) {
  double scale = min(1.0, maxSide / max(width, height));
  int canvasWidth = (width * scale).round();
  int canvasHeight = (height * scale).round();
  JSObject canvas =
      _document.callMethod<JSObject>('createElement'.toJS, 'canvas'.toJS);
  canvas.setProperty('width'.toJS, canvasWidth.toJS);
  canvas.setProperty('height'.toJS, canvasHeight.toJS);
  canvas.callMethod<JSObject>('getContext'.toJS, '2d'.toJS).callMethodVarArgs(
      'drawImage'.toJS,
      [image, 0.toJS, 0.toJS, canvasWidth.toJS, canvasHeight.toJS]);
  return canvas;
}

// Uses the ZXing core decoder directly. BrowserQRCodeReader.decodeFromImageUrl
// in 0.19.1 treats an <img> as a video (videoWidth is undefined, not 0),
// draws an empty frame and never finds the QR.
String? _decodeCanvas(JSObject canvas) {
  JSObject hints =
      globalContext.getProperty<JSFunction>('Map'.toJS).callAsConstructor();
  hints.callMethod(
      'set'.toJS,
      globalContext
          .getProperty<JSObject>('ZXing'.toJS)
          .getProperty<JSObject>('DecodeHintType'.toJS)
          .getProperty<JSAny>('TRY_HARDER'.toJS),
      true.toJS);
  try {
    JSObject bitmap = _newZXing(
        'BinaryBitmap',
        _newZXing('HybridBinarizer',
            _newZXing('HTMLCanvasElementLuminanceSource', canvas)));
    JSObject result = _newZXing('QRCodeReader')
        .callMethod<JSObject>('decode'.toJS, bitmap, hints);
    return result.callMethod<JSString>('getText'.toJS).toDart;
  } catch (e) {
    // ZXing throws NotFoundException when there is no QR in the image
    return null;
  }
}

// Returns null when the image has no readable QR
Future<String?> _tryDecodeImageUrl(String url) async {
  await _loadZXing();
  JSObject image = await _loadImage(url);
  int width = image.getProperty<JSNumber>('naturalWidth'.toJS).toDartInt;
  int height = image.getProperty<JSNumber>('naturalHeight'.toJS).toDartInt;
  if (width == 0 || height == 0) {
    throw VietQrImageException('Không mở được ảnh.');
  }
  // Large photos are slow to decode, try a scaled down copy first
  String? text =
      _decodeCanvas(_drawOnCanvas(image, width, height, _maxImageSide));
  // A small QR in a big photo can be lost when scaled down, retry larger.
  // iOS blanks canvases above ~16.7M pixels, so cap the retry size
  if (text == null && max(width, height) > _maxImageSide) {
    text =
        _decodeCanvas(_drawOnCanvas(image, width, height, _maxRetryImageSide));
  }
  return text == null || text.isEmpty ? null : text;
}

Future<String> _decodeImageUrl(String url) async {
  String? text = await _tryDecodeImageUrl(url);
  if (text == null) {
    throw VietQrImageException(
        'Không tìm thấy mã QR trong ảnh. Thử cắt sát mã QR rồi chọn lại.');
  }
  return text;
}

Future<String> readQrFromImagePath(String path) {
  // On web, image_picker returns a blob: URL as the path
  return _decodeImageUrl(path);
}

JSObject get _urlApi => globalContext.getProperty<JSObject>('URL'.toJS);

// Null when the blob is not an image or has no readable QR
Future<String?> _tryDecodeBlob(JSObject blob) async {
  String url =
      _urlApi.callMethod<JSString>('createObjectURL'.toJS, blob).toDart;
  try {
    return await _tryDecodeImageUrl(url);
  } on VietQrImageException {
    return null;
  } finally {
    _urlApi.callMethod('revokeObjectURL'.toJS, url.toJS);
  }
}

// Image URLs in copied HTML (<img src>) or a text/uri-list
List<String> _imageUrlsInText(String text) {
  return RegExp(
          r"""data:image/[A-Za-z0-9.+-]+;base64,[A-Za-z0-9+/=]+|https?://[^"'\s<>]+""")
      .allMatches(text)
      .map((match) => match.group(0)!.replaceAll('&amp;', '&'))
      .toList();
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
    List<String> seenTypes = [];
    bool sawImage = false;
    String? plainText;
    for (JSObject item in items) {
      List<String> types = item
          .getProperty<JSArray<JSString>>('types'.toJS)
          .toDart
          .map((type) => type.toDart)
          .toList();
      seenTypes.addAll(types);
      // iOS can expose a copied photo under a type other than image/png,
      // so every non-text type is tried as an image, images before text
      List<String> ordered = [
        ...types.where((type) => !type.startsWith('text/')),
        ...types.where((type) => type.startsWith('text/')),
      ];
      for (String type in ordered) {
        JSObject blob;
        try {
          blob = await item
              .callMethod<JSPromise<JSObject>>('getType'.toJS, type.toJS)
              .toDart;
        } catch (e) {
          continue;
        }
        if (!type.startsWith('text/')) {
          String? text = await _tryDecodeBlob(blob);
          if (text != null) return text;
          if (type.startsWith('image/')) sawImage = true;
          continue;
        }
        String content =
            (await blob.callMethod<JSPromise<JSString>>('text'.toJS).toDart)
                .toDart;
        if (type == 'text/plain') {
          if (content.trim().isNotEmpty) plainText ??= content;
          continue;
        }
        for (String url in _imageUrlsInText(content)) {
          String? text;
          try {
            text = await _tryDecodeImageUrl(url);
          } on VietQrImageException {
            text = null;
          }
          if (text != null) return text;
        }
      }
    }
    if (plainText != null) return plainText;
    if (sawImage) {
      throw VietQrImageException('Không tìm thấy mã QR trong ảnh đã copy.');
    }
    String found = seenTypes.isEmpty ? 'trống' : seenTypes.join(', ');
    throw VietQrImageException(
        'Clipboard không có ảnh QR hay chuỗi QR (iOS trả về: $found).');
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
