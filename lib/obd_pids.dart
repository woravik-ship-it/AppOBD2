/// OBD-II PID definitions (Mode 01 — Show current data).
/// name / unit / decoder(bytes A,B,C,D) -> double value
class ObdPid {
  final String mode;
  final String pid;
  final String name;
  final String unit;
  final double Function(List<int> bytes) decode;

  const ObdPid({
    required this.mode,
    required this.pid,
    required this.name,
    required this.unit,
    required this.decode,
  });

  String get command => '$mode$pid\r';
}

/// ชุด PID หลักสำหรับ dashboard — decode ตาม SAE J1979
const List<ObdPid> kDefaultPids = [
  ObdPid(
    mode: '01',
    pid: '0C',
    name: 'RPM',
    unit: 'rpm',
    decode: _rpm,
  ),
  ObdPid(
    mode: '01',
    pid: '0D',
    name: 'Speed',
    unit: 'km/h',
    decode: _speed,
  ),
  ObdPid(
    mode: '01',
    pid: '04',
    name: 'Engine Load',
    unit: '%',
    decode: _load,
  ),
  ObdPid(
    mode: '01',
    pid: '05',
    name: 'Coolant',
    unit: '°C',
    decode: _temp,
  ),
  ObdPid(
    mode: '01',
    pid: '0F',
    name: 'Intake Air',
    unit: '°C',
    decode: _temp,
  ),
  ObdPid(
    mode: '01',
    pid: '11',
    name: 'Throttle',
    unit: '%',
    decode: _throttle,
  ),
  ObdPid(
    mode: '01',
    pid: '2F',
    name: 'Fuel Level',
    unit: '%',
    decode: _throttle,
  ),
  ObdPid(
    mode: '01',
    pid: '42',
    name: 'Battery',
    unit: 'V',
    decode: _voltage,
  ),
];

double _rpm(List<int> b) => b.length >= 2 ? (b[0] * 256 + b[1]) / 4.0 : 0;
double _speed(List<int> b) => b.isNotEmpty ? b[0].toDouble() : 0;
double _load(List<int> b) => b.isNotEmpty ? b[0] * 100.0 / 255.0 : 0;
double _temp(List<int> b) => b.isNotEmpty ? b[0] - 40.0 : 0;
double _throttle(List<int> b) => b.isNotEmpty ? b[0] * 100.0 / 255.0 : 0;
double _voltage(List<int> b) =>
    b.length >= 2 ? (b[0] * 256 + b[1]) / 1000.0 : 0;

/// แปลง response `41 0C 1A F8` (อาจมี echo/prompt ปน) -> bytes [0x1A, 0xF8]
List<int> parseObdResponse(String raw, String mode, String pid) {
  final clean = raw
      .replaceAll('>', '')
      .replaceAll('\r', ' ')
      .replaceAll('\n', ' ')
      .replaceAll('SEARCHING...', ' ')
      .trim();
  final tokens =
      clean.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
  // หา header `41 <PID>` (mode+0x40) แล้วเอาค่าหลังจากนั้น
  final wantMode = (int.parse(mode, radix: 16) + 0x40)
      .toRadixString(16)
      .toUpperCase()
      .padLeft(2, '0');
  final wantPid = pid.toUpperCase().padLeft(2, '0');
  for (var i = 0; i + 1 < tokens.length; i++) {
    if (tokens[i].toUpperCase() == wantMode &&
        tokens[i + 1].toUpperCase() == wantPid) {
      final out = <int>[];
      for (var j = i + 2; j < tokens.length; j++) {
        final v = int.tryParse(tokens[j], radix: 16);
        if (v == null) break;
        out.add(v);
      }
      return out;
    }
  }
  return [];
}
