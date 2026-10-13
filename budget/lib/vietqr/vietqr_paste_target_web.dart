import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:budget/vietqr/vietqr_image_reader.dart';
import 'package:budget/vietqr/vietqr_image_reader_web.dart';
import 'package:flutter/widgets.dart';

const String _styleId = 'vietqr-paste-style';
const String _className = 'vietqr-paste';

JSObject get _document => globalContext.getProperty<JSObject>('document'.toJS);

String _cssColor(Color color) =>
    'rgba(${color.red},${color.green},${color.blue},${color.opacity})';

// Shows the placeholder while the box is empty
void _addStyleOnce() {
  if (_document.callMethod<JSObject?>('getElementById'.toJS, _styleId.toJS) !=
      null) return;
  JSObject style =
      _document.callMethod<JSObject>('createElement'.toJS, 'style'.toJS);
  style.setProperty('id'.toJS, _styleId.toJS);
  style.setProperty(
      'textContent'.toJS,
      ('.$_className:empty::before{content:attr(data-placeholder);'
              'opacity:.85;pointer-events:none}')
          .toJS);
  _document
      .getProperty<JSObject>('head'.toJS)
      .callMethod('appendChild'.toJS, style);
}

// DataTransferItemList and FileList are array-like, not JS arrays
List<JSObject> _arrayLike(JSObject? list) {
  if (list == null) return [];
  int length = list.getProperty<JSNumber>('length'.toJS).toDartInt;
  return [
    for (int i = 0; i < length; i++) list.getProperty<JSObject>(i.toJS),
  ];
}

Future<String> _readPasteEvent(JSObject event) {
  JSObject? data = event.getProperty<JSObject?>('clipboardData'.toJS);
  if (data == null) {
    return Future.error(
        VietQrImageException('Không đọc được nội dung vừa dán.'));
  }
  for (JSObject item in _arrayLike(data.getProperty<JSObject?>('items'.toJS))) {
    String kind = item.getProperty<JSString>('kind'.toJS).toDart;
    String type = item.getProperty<JSString>('type'.toJS).toDart;
    if (kind == 'file' && type.startsWith('image/')) {
      JSObject? file = item.callMethod<JSObject?>('getAsFile'.toJS);
      if (file != null) return readQrFromImageBlob(file);
    }
  }
  for (JSObject file in _arrayLike(data.getProperty<JSObject?>('files'.toJS))) {
    String type = file.getProperty<JSString>('type'.toJS).toDart;
    if (type.isEmpty || type.startsWith('image/')) {
      return readQrFromImageBlob(file);
    }
  }
  String text =
      data.callMethod<JSString>('getData'.toJS, 'text/plain'.toJS).toDart;
  if (text.trim().isNotEmpty) return Future.value(text);
  List<String> types = data
      .getProperty<JSArray<JSString>>('types'.toJS)
      .toDart
      .map((type) => type.toDart)
      .toList();
  String found = types.isEmpty ? 'trống' : types.join(', ');
  return Future.error(VietQrImageException(
      'Nội dung vừa dán không có ảnh hay chuỗi QR (iOS trả về: $found).'));
}

// A real contenteditable element: long-pressing it shows the iOS "Paste"
// callout, and its paste event carries copied photos that the async
// clipboard API hides on iOS Safari
Widget buildVietQrPasteTarget({
  required String placeholder,
  required Color textColor,
  required Color borderColor,
  required void Function(Future<String> result) onPaste,
}) {
  return SizedBox(
    height: 96,
    child: HtmlElementView.fromTagName(
      tagName: 'div',
      onElementCreated: (Object created) {
        _addStyleOnce();
        JSObject element = created as JSObject;
        element.setProperty('className'.toJS, _className.toJS);
        element.callMethod(
            'setAttribute'.toJS, 'contenteditable'.toJS, 'true'.toJS);
        // Allows the paste callout without bringing up the keyboard
        element.callMethod('setAttribute'.toJS, 'inputmode'.toJS, 'none'.toJS);
        element.callMethod(
            'setAttribute'.toJS, 'data-placeholder'.toJS, placeholder.toJS);
        JSObject style = element.getProperty<JSObject>('style'.toJS);
        Map<String, String> css = {
          'width': '100%',
          'height': '100%',
          'boxSizing': 'border-box',
          'display': 'flex',
          'alignItems': 'center',
          'justifyContent': 'center',
          'textAlign': 'center',
          'padding': '12px',
          'border': '2px dashed ${_cssColor(borderColor)}',
          'borderRadius': '16px',
          'color': _cssColor(textColor),
          'fontSize': '15px',
          'fontFamily': '-apple-system, system-ui, sans-serif',
          'outline': 'none',
          'caretColor': 'transparent',
          'overflow': 'hidden',
          'webkitUserSelect': 'text',
          'userSelect': 'text',
        };
        css.forEach((key, value) => style.setProperty(key.toJS, value.toJS));
        element.callMethod(
            'addEventListener'.toJS,
            'paste'.toJS,
            ((JSObject event) {
              event.callMethod('preventDefault'.toJS);
              onPaste(_readPasteEvent(event));
            }).toJS);
        // Keep the box empty if anything gets typed or dropped in
        element.callMethod(
            'addEventListener'.toJS,
            'input'.toJS,
            ((JSObject event) {
              element.setProperty('textContent'.toJS, ''.toJS);
            }).toJS);
      },
    ),
  );
}
