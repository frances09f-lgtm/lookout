import 'package:flutter_test/flutter_test.dart';
import 'package:lookout/domain/time_format.dart';

void main() {
  test('renders 12-hour AM/PM, never 24-hour', () {
    expect(fmtAppTime(DateTime(2026, 10, 29, 21, 54)), '29/10 9:54 PM');
    expect(fmtAppTime(DateTime(2026, 10, 29, 9, 5)), '29/10 9:05 AM');
    expect(fmtAppTime(DateTime(2026, 10, 29, 0, 7)), '29/10 12:07 AM');
    expect(fmtAppTime(DateTime(2026, 10, 29, 12, 0)), '29/10 12:00 PM');
    expect(fmtAppTime(DateTime(2026, 10, 29, 13, 59)), '29/10 1:59 PM');
    expect(fmtAppTime(DateTime(2026, 10, 29, 23, 59)), '29/10 11:59 PM');
  });
}
