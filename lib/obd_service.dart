import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_bluetooth_serial_plus/flutter_bluetooth_serial_plus.dart';

import 'obd_pids.dart';

/// สถานะการเชื่อมต่อ adapter
enum ObdConnState { idle, connecting, connected, error }

/// คลุม Bluetooth SPP ไปยัง ELM327 + ส่ง AT/PID command แบบ request/response
class ObdService {
  BluetoothConnection? _conn;
  final _rx = StringBuffer();
  final _lineCtrl = StreamController<String>.broadcast();
  Completer<String>? _pending;

  ObdConnState state = ObdConnState.idle;
  String statusMsg = '';

  Stream<String> get rawLines => _lineCtrl.stream;

  Future<List<BluetoothDevice>> bondedDevices() =>
      FlutterBluetoothSerial.instance.getBondedDevices();

  /// pair ใหม่: เปิด system settings ให้ user pair ก่อน แล้วกด refresh
  Future<void> openBluetoothSettings() =>
      FlutterBluetoothSerial.instance.openSettings();

  Future<void> connect(BluetoothDevice device) async {
    disconnect();
    state = ObdConnState.connecting;
    statusMsg = 'Connecting to ${device.name ?? device.address}...';
    try {
      _conn = await BluetoothConnection.toAddress(device.address);
      state = ObdConnState.connected;
      statusMsg = 'Connected — init ELM327...';
      _conn!.input.listen(_onData, onDone: disconnect);
      await initElm();
      statusMsg = 'Ready';
    } catch (e) {
      state = ObdConnState.error;
      statusMsg = 'Connect failed: $e';
      rethrow;
    }
  }

  void _onData(Uint8List data) {
    final chunk = ascii.decode(data, allowInvalid: true);
    _rx.write(chunk);
    // ELM327 จบ response ด้วย prompt `>`
    var s = _rx.toString();
    var idx = s.indexOf('>');
    while (idx >= 0) {
      final line = s.substring(0, idx);
      _lineCtrl.add(line);
      if (_pending != null && !_pending!.isCompleted) {
        _pending!.complete(line);
      }
      s = s.substring(idx + 1);
      idx = s.indexOf('>');
    }
    _rx
      ..clear()
      ..write(s);
  }

  /// ส่ง 1 command แล้วรอ response จน prompt `>` (timeout 3s)
  Future<String> send(String cmd,
      {Duration timeout = const Duration(seconds: 3)}) async {
    final conn = _conn;
    if (conn == null || !conn.isConnected) {
      throw StateError('Not connected');
    }
    _pending = Completer<String>();
    conn.output.add(ascii.encode(cmd.endsWith('\r') ? cmd : '$cmd\r'));
    await conn.output.allSent;
    return _pending!.future.timeout(timeout);
  }

  /// init ELM327: reset + ตั้ง protocol auto + ปิด echo/linefeed ให้ parse ง่าย
  Future<void> initElm() async {
    for (final cmd in ['ATZ', 'ATE0', 'ATL0', 'ATS0', 'ATH0', 'ATSP0']) {
      try {
        await send(cmd, timeout: const Duration(seconds: 5));
      } catch (_) {
        // ATZ บูตช้า — ลองคำสั่งถัดไปต่อได้
      }
      await Future.delayed(const Duration(milliseconds: 120));
    }
    // warm-up: ถาม voltage 1 ครั้งให้ adapter เลือก protocol
    try {
      await send('ATRV');
    } catch (_) {}
  }

  /// อ่าน 1 PID -> ค่าตัวเลข (null = อ่านไม่ได้)
  Future<double?> readPid(ObdPid pid) async {
    try {
      final raw = await send(pid.command);
      if (raw.contains('NO DATA') ||
          raw.contains('?') ||
          raw.contains('ERROR')) {
        return null;
      }
      final bytes = parseObdResponse(raw, pid.mode, pid.pid);
      if (bytes.isEmpty) return null;
      return pid.decode(bytes);
    } catch (_) {
      return null;
    }
  }

  void disconnect() {
    try {
      _conn?.dispose();
    } catch (_) {}
    _conn = null;
    if (state == ObdConnState.connected ||
        state == ObdConnState.connecting) {
      state = ObdConnState.idle;
      statusMsg = 'Disconnected';
    }
  }

  void dispose() {
    disconnect();
    _lineCtrl.close();
  }
}
