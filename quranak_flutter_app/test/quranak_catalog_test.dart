import 'package:flutter_test/flutter_test.dart';
import 'package:quranak_app/main.dart';

void main() {
  test('bundled Quran index contains all 114 surahs', () {
    expect(all114Surahs.length, 114);
    expect(all114Surahs.first['plain'], 'الفاتحة');
    expect(all114Surahs.last['plain'], 'الناس');
  });
}
