import 'package:budget/database/searchFolding.dart';
import 'package:budget/database/tables.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('foldDiacritics maps Vietnamese letters to ASCII', () {
    expect(foldDiacritics('Cà PHÊ Sữa Đá'), 'ca phe sua da');
    expect(foldDiacritics('Tiền điện tháng 10'), 'tien dien thang 10');
    expect(diacriticFolds.length, 134);
  });

  test('hasFoldableDiacritics', () {
    expect(hasFoldableDiacritics('ca phe'), false);
    expect(hasFoldableDiacritics('cà phe'), true);
    expect(hasFoldableDiacritics('Đ'), true);
  });

  group('SQL', () {
    late FinanceDatabase db;
    setUp(() => db = FinanceDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    Future<Object?> eval(Expression expression) async {
      GenerationContext context = GenerationContext.fromDb(db);
      expression.writeInto(context);
      QueryRow row = await db
          .customSelect('SELECT ' + context.sql + ' AS r',
              variables: context.introducedVariables)
          .getSingle();
      Object? value = row.data['r'];
      return value is int ? value == 1 : value;
    }

    test('searchGlobPattern escapes GLOB wildcards', () async {
      expect(searchGlobPattern('1*'), '*1[*]*');
      expect(await eval(Constant('50% off [x]').likeSearch('50% off [')), true);
      expect(await eval(Constant('abc').likeSearch('a?c')), false);
      expect(await eval(Constant('a?c').likeSearch('a?c')), true);
    });

    test('likeSearch on upper case and every Vietnamese vowel', () async {
      expect(await eval(Constant('ĐỔ XĂNG Ưu Ỷ').likeSearch('do xang uu y')),
          true);
      expect(
          await eval(Constant('Tiền điện tháng 10').likeSearch('DIEN THANG 1')),
          true);
    });

    test('likeSearchTerms with && and ||', () async {
      Expression<String> text = Constant('Cà phê sữa đá');
      expect(await eval(text.likeSearchTerms('ca phe && da')), true);
      expect(await eval(text.likeSearchTerms('ca phe && tra')), false);
      expect(await eval(text.likeSearchTerms('tra || sua')), true);
      expect(await eval(text.likeSearchTerms('tra || banh')), false);
      expect(await eval(text.likeSearchTerms('tra && x || phe && da')), true);
      expect(await eval(text.likeSearchTerms('phê')), true);
    });

    test('likeSearch', () async {
      Expression<String> text = Constant('Cà phê sữa đá');
      expect(await eval(text.likeSearch('ca phe')), true);
      expect(await eval(text.likeSearch('SUA DA')), true);
      expect(await eval(text.likeSearch('cà phê')), true);
      expect(await eval(text.likeSearch('CÀ PHÊ')), false);
      expect(await eval(text.likeSearch('cà phe')), false);
      expect(await eval(text.likeSearch('tra')), false);
      expect(await eval(Constant('Coffee').likeSearch('coff')), true);
    });
  });
}
