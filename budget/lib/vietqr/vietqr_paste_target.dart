// A box to long-press and choose "Paste" in, for when the clipboard API
// cannot see a copied image (iOS Safari). Only shown on web.
export 'vietqr_paste_target_stub.dart'
    if (dart.library.js_interop) 'vietqr_paste_target_web.dart';
