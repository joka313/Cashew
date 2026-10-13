import 'package:budget/functions.dart';
import 'package:budget/struct/settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  DateTime date = DateTime(2025, 3, 5, 14, 7);

  tearDown(() => appStateSettings.remove("dateFormat"));

  test('default keeps worded dates', () {
    appStateSettings["dateFormat"] = "default";
    expect(getNumericDateFormat(includeYear: false), null);
    expect(getWordedDateShort(date, showTodayTomorrow: false), 'Mar 5');
  });

  test('numeric formats with and without year', () {
    appStateSettings["dateFormat"] = "dd/MM/yyyy";
    expect(getWordedDateShort(date, showTodayTomorrow: false), '05/03');
    expect(
        getWordedDateShort(date, includeYear: true, showTodayTomorrow: false),
        '05/03/2025');
    appStateSettings["dateFormat"] = "MM/dd/yyyy";
    expect(getWordedDateShort(date, showTodayTomorrow: false), '03/05');
    appStateSettings["dateFormat"] = "yyyy-MM-dd";
    expect(
        getWordedDateShort(date, includeYear: true, showTodayTomorrow: false),
        '2025-03-05');
    expect(
        getWordedDateShortMore(date,
            includeYear: true, showTodayTomorrow: false),
        '2025-03-05');
  });

  test('unknown value falls back to worded', () {
    appStateSettings["dateFormat"] = "nonsense";
    expect(getNumericDateFormat(includeYear: true), null);
  });
}
