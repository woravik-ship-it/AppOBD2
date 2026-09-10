import 'package:app_obd2/obd_pids.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('RPM decode: 41 0C 1A F8 -> 1726 rpm', () {
    final bytes = parseObdResponse('41 0C 1A F8 >', '01', '0C');
    expect(bytes, [0x1A, 0xF8]);
    final rpm = kDefaultPids.firstWhere((p) => p.pid == '0C').decode(bytes);
    expect(rpm, (0x1A * 256 + 0xF8) / 4.0);
  });

  test('Speed decode: 41 0D 3C -> 60 km/h', () {
    final bytes = parseObdResponse('41 0D 3C >', '01', '0D');
    expect(bytes, [0x3C]);
    expect(kDefaultPids.firstWhere((p) => p.pid == '0D').decode(bytes), 60.0);
  });

  test('parse ignores echo + SEARCHING noise', () {
    final bytes = parseObdResponse('010C\rSEARCHING...\r41 0C 10 00 >', '01', '0C');
    expect(bytes, [0x10, 0x00]);
  });

  test('NO DATA -> empty bytes', () {
    expect(parseObdResponse('NO DATA >', '01', '0C'), isEmpty);
  });
}
