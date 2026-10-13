import 'package:budget/vietqr/vietqr_parser.dart';
import 'package:flutter_test/flutter_test.dart';

const String sampleQr =
    '00020101021238530010A0000007270123000697041601092576788590208QRIBFTTA5303704540410005802VN62150811Chuyen tien6304BBB8';

void main() {
  group('parseVietQr', () {
    test('decodes the sample VietQR', () {
      VietQrData data = parseVietQr(sampleQr);
      expect(data.bin, '970416');
      expect(data.bankCode, 'acb');
      expect(data.bankName, 'ACB');
      expect(data.account, '257678859');
      expect(data.amount, 1000);
      expect(data.note, 'Chuyen tien');
      expect(data.name, '');
      expect(data.crcValid, true);
    });

    test('ignores surrounding whitespace', () {
      expect(parseVietQr('  ' + sampleQr + '\n').crcValid, true);
    });

    test('flags an invalid CRC when one character is changed', () {
      // Change the amount 1000 -> 9000, keeping the original CRC
      String tampered = sampleQr.replaceFirst('54041000', '54049000');
      expect(tampered, isNot(sampleQr));
      VietQrData data = parseVietQr(tampered);
      expect(data.amount, 9000);
      expect(data.crcValid, false);
    });

    test('throws when tag 38 is missing', () {
      String noTag38 = '000201010212'
          '5303704540410005802VN62150811Chuyen tien6304ABCD';
      expect(
        () => parseVietQr(noTag38),
        throwsA(isA<VietQrFormatException>().having(
            (e) => e.message, 'message', contains('thiếu trường 38'))),
      );
    });

    test('static QR without tag 54 has no amount', () {
      String noAmount = sampleQr.replaceFirst('54041000', '');
      expect(parseVietQr(noAmount).amount, null);
    });
  });

  group('vietQrCrc16', () {
    test('matches the CRC embedded in the sample', () {
      int crcPos = sampleQr.lastIndexOf('6304');
      expect(vietQrCrc16(sampleQr.substring(0, crcPos + 4)), 'BBB8');
    });
  });

  group('removeVietnameseDiacritics', () {
    test('maps all Vietnamese letters to ASCII', () {
      expect(removeVietnameseDiacritics('Chuyển tiền ăn trưa đầy đủ'),
          'Chuyen tien an trua day du');
      expect(removeVietnameseDiacritics('NGUYỄN VĂN ĐỨC'), 'NGUYEN VAN DUC');
      expect(removeVietnameseDiacritics('Ỳ ý ỵ ỷ ỹ ơ ợ ư ự'), 'Y y y y y o o u u');
    });

    test('handles decomposed (NFD) input', () {
      expect(removeVietnameseDiacritics('Tiền'), 'Tien');
    });
  });

  group('buildVietQrTransferLink', () {
    test('builds the MBBank deeplink from the sample', () {
      VietQrData data = parseVietQr(sampleQr);
      expect(
        buildVietQrTransferLink(
          account: data.account,
          bankCode: data.bankCode,
          amount: data.amount,
          note: data.note,
          appUrl: 'https://joka313.github.io/Cashew/',
        ),
        'https://dl.vietqr.io/pay?app=mb&ba=257678859@acb&am=1000'
        '&tn=Chuyen%20tien'
        '&url=https%3A%2F%2Fjoka313.github.io%2FCashew%2F',
      );
    });

    test('removes diacritics, encodes spaces as %20 and uppercases bn', () {
      String? link = buildVietQrTransferLink(
        account: '0123456789',
        bankCode: 'vpb',
        amount: 50000,
        note: 'Tiền ăn trưa',
        name: 'Nguyễn Văn A',
      );
      expect(link, contains('tn=Tien%20an%20trua'));
      expect(link, contains('bn=NGUYEN%20VAN%20A'));
      expect(link, contains('am=50000'));
      expect(link, isNot(contains('+')));
    });

    test('cannot build a link without an amount', () {
      expect(
          buildVietQrTransferLink(
              account: '257678859', bankCode: 'acb', amount: null),
          null);
      expect(
          buildVietQrTransferLink(
              account: '257678859', bankCode: 'acb', amount: 0),
          null);
    });

    test('survives Uri.parse unchanged (used for the Link href)', () {
      String link = buildVietQrTransferLink(
        account: '257678859',
        bankCode: 'acb',
        amount: 1000,
        note: 'Tiền điện tháng 10',
        name: 'Trần Thị B',
        appUrl: 'https://joka313.github.io/Cashew/#/home',
      )!;
      expect(Uri.parse(link).toString(), link);
      expect(Uri.parse(link).queryParameters['tn'], 'Tien dien thang 10');
      expect(Uri.parse(link).queryParameters['bn'], 'TRAN THI B');
      expect(Uri.parse(link).queryParameters['ba'], '257678859@acb');
    });

    test('uses kVietQrBankApp as the app code', () {
      String? link = buildVietQrTransferLink(
          account: '1', bankCode: 'mb', amount: 1);
      expect(link, startsWith('https://dl.vietqr.io/pay?app=$kVietQrBankApp&'));
    });
  });
}
