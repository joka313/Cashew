// VietQR (EMVCo TLV) decoder and bank deeplink builder.
// Ported from vietqr-reference.html (tlv, crc16, decode, BANKS).

// The only place the banking app used for transfers is configured.
const String kVietQrBankApp = 'mb';

const String kVietQrNapasId = 'A000000727';

// BIN -> [VietQR bank code, display name]
const Map<String, List<String>> vietQrBanks = {
  '970436': ['vcb', 'Vietcombank'],
  '970415': ['icb', 'VietinBank'],
  '970418': ['bidv', 'BIDV'],
  '970405': ['vba', 'Agribank'],
  '970422': ['mb', 'MBBank'],
  '970407': ['tcb', 'Techcombank'],
  '970416': ['acb', 'ACB'],
  '970432': ['vpb', 'VPBank'],
  '970423': ['tpb', 'TPBank'],
  '970403': ['stb', 'Sacombank'],
  '970437': ['hdb', 'HDBank'],
  '970448': ['ocb', 'OCB'],
  '970426': ['msb', 'MSB'],
  '970441': ['vib', 'VIB'],
  '970443': ['shb', 'SHB'],
  '970431': ['eib', 'Eximbank'],
  '970429': ['scb', 'SCB'],
  '970440': ['seab', 'SeABank'],
  '970449': ['lpb', 'LPBank'],
  '970428': ['nab', 'Nam A Bank'],
  '970409': ['bab', 'Bac A Bank'],
  '970425': ['abb', 'ABBANK'],
  '970427': ['vab', 'VietABank'],
  '970452': ['klb', 'KienlongBank'],
  '970419': ['ncb', 'NCB'],
  '970412': ['pvcb', 'PVcomBank'],
  '970454': ['vccb', 'Ban Viet'],
  '970433': ['vietbank', 'VietBank'],
  '970400': ['sgicb', 'Saigonbank'],
  '970430': ['pgb', 'PGBank'],
  '970406': ['dob', 'Vikki'],
  '970444': ['cbb', 'CBBank'],
  '970408': ['gpb', 'GPBank'],
  '970414': ['oceanbank', 'MBV'],
  '970424': ['shbvn', 'Shinhan'],
  '546034': ['cake', 'CAKE'],
  '546035': ['ubank', 'Ubank'],
  '963388': ['timo', 'Timo'],
  '971005': ['viettelmoney', 'Viettel Money'],
};

// Display name of kVietQrBankApp, looked up from vietQrBanks
String get vietQrBankAppName {
  for (List<String> bank in vietQrBanks.values) {
    if (bank[0] == kVietQrBankApp) return bank[1];
  }
  return kVietQrBankApp.toUpperCase();
}

class VietQrFormatException implements Exception {
  VietQrFormatException(this.message);
  final String message;

  @override
  String toString() => message;
}

class VietQrData {
  VietQrData({
    required this.bin,
    required this.bankCode,
    required this.bankName,
    required this.account,
    required this.amount,
    required this.note,
    required this.name,
    required this.crcValid,
  });

  final String bin;
  // Lowercase VietQR bank code (falls back to the BIN when unknown)
  final String bankCode;
  // Empty when the BIN is not in vietQrBanks
  final String bankName;
  final String account;
  // Null for static QR codes without an amount
  final double? amount;
  final String note;
  final String name;
  final bool crcValid;
}

// Behaves like JS substr: clamps instead of throwing when out of range
String _substr(String s, int start, int length) {
  if (start >= s.length) return "";
  int end = start + length;
  return s.substring(start, end > s.length ? s.length : end);
}

Map<String, String> vietQrTlv(String s) {
  Map<String, String> o = {};
  int i = 0;
  while (i + 4 <= s.length) {
    String t = _substr(s, i, 2);
    // Same as JS parseInt: read leading digits, stop if there are none
    String? digits = RegExp(r'^\d+').stringMatch(_substr(s, i + 2, 2));
    if (digits == null) break;
    int n = int.parse(digits);
    if (!o.containsKey(t)) o[t] = _substr(s, i + 4, n);
    i += 4 + n;
  }
  return o;
}

String vietQrCrc16(String str) {
  int c = 0xFFFF;
  for (int i = 0; i < str.length; i++) {
    c ^= str.codeUnitAt(i) << 8;
    for (int j = 0; j < 8; j++) {
      c = (c & 0x8000) != 0 ? ((c << 1) ^ 0x1021) & 0xFFFF : (c << 1) & 0xFFFF;
    }
  }
  return c.toRadixString(16).toUpperCase().padLeft(4, '0');
}

VietQrData parseVietQr(String input) {
  String s = input.trim();
  Map<String, String> top = vietQrTlv(s);
  if (top['38'] == null) {
    throw VietQrFormatException(
        'Không phải mã VietQR chuyển khoản (thiếu trường 38). Có thể là QR của ví hoặc QR thanh toán thẻ.');
  }
  Map<String, String> m = vietQrTlv(top['38']!);
  if (m['00'] != kVietQrNapasId) {
    print('VietQR: Napas id does not match: ' + m['00'].toString());
  }
  Map<String, String> c = vietQrTlv(m['01'] ?? '');
  Map<String, String> add = top['62'] != null ? vietQrTlv(top['62']!) : {};
  int crcPos = s.lastIndexOf('6304');
  bool crcValid = crcPos >= 0 &&
      vietQrCrc16(s.substring(0, crcPos + 4)) ==
          _substr(s, crcPos + 4, 4).toUpperCase();

  String bin = c['00'] ?? '';
  List<String>? bank = vietQrBanks[bin];
  return VietQrData(
    bin: bin,
    bankCode: bank?[0] ?? bin,
    bankName: bank?[1] ?? '',
    account: c['01'] ?? '',
    amount: double.tryParse(top['54'] ?? ''),
    note: add['08'] ?? '',
    name: top['59'] ?? '',
    crcValid: crcValid,
  );
}

const String _vietnameseChars =
    'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ'
    'ÀÁẠẢÃÂẦẤẬẨẪĂẰẮẶẲẴÈÉẸẺẼÊỀẾỆỂỄÌÍỊỈĨÒÓỌỎÕÔỒỐỘỔỖƠỜỚỢỞỠÙÚỤỦŨƯỪỨỰỬỮỲÝỴỶỸĐ';
const String _vietnameseCharsAscii =
    'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd'
    'AAAAAAAAAAAAAAAAAEEEEEEEEEEEIIIIIOOOOOOOOOOOOOOOOOUUUUUUUUUUUYYYYYD';

String removeVietnameseDiacritics(String input) {
  StringBuffer out = StringBuffer();
  for (int rune in input.runes) {
    String char = String.fromCharCode(rune);
    int index = _vietnameseChars.indexOf(char);
    out.write(index >= 0 ? _vietnameseCharsAscii[index] : char);
  }
  // Strip combining marks left over from decomposed (NFD) input
  return out.toString().replaceAll(RegExp('[̀-ͯ]'), '');
}

String _formatDeeplinkAmount(double amount) {
  if (amount == amount.roundToDouble()) return amount.toInt().toString();
  return amount.toString();
}

// Returns null when a transfer link cannot be built (MBBank requires an amount)
String? buildVietQrTransferLink({
  required String account,
  required String bankCode,
  required double? amount,
  String note = '',
  String name = '',
  String? appUrl,
  String app = kVietQrBankApp,
}) {
  if (amount == null || amount <= 0) return null;
  if (account.isEmpty || bankCode.isEmpty) return null;

  // Uri.encodeComponent encodes spaces as %20 (never +)
  List<String> query = [
    'app=' + Uri.encodeComponent(app),
    'ba=' + Uri.encodeComponent(account) + '@' + Uri.encodeComponent(bankCode),
    'am=' + _formatDeeplinkAmount(amount),
  ];
  String tn = removeVietnameseDiacritics(note).trim();
  if (tn.isNotEmpty) query.add('tn=' + Uri.encodeComponent(tn));
  String bn = removeVietnameseDiacritics(name).trim().toUpperCase();
  if (bn.isNotEmpty) query.add('bn=' + Uri.encodeComponent(bn));
  if (appUrl != null && appUrl.isNotEmpty) {
    query.add('url=' + Uri.encodeComponent(appUrl));
  }
  return 'https://dl.vietqr.io/pay?' + query.join('&');
}
