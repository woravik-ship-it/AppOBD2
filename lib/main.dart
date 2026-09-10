import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_bluetooth_serial_plus/flutter_bluetooth_serial_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'obd_pids.dart';
import 'obd_service.dart';
import 'supercar_gauge.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initBackgroundService();
  runApp(const ObdApp());
}

Future<void> _initBackgroundService() async {
  final service = FlutterBackgroundService();
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: _onServiceStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: 'obd2_foreground',
      initialNotificationTitle: 'AppOBD2',
      initialNotificationContent: 'กำลังเชื่อมต่อ OBD2...',
      foregroundServiceNotificationId: 888,
      foregroundServiceTypes: [AndroidForegroundType.connectedDevice],
    ),
    iosConfiguration: IosConfiguration(autoStart: false, onForeground: _onServiceStart, onBackground: _onIosBackground),
  );
}

@pragma('vm:entry-point')
void _onServiceStart(ServiceInstance service) async {
  service.on('stop').listen((_) async {
    await service.stopSelf();
  });
}

@pragma('vm:entry-point')
bool _onIosBackground(ServiceInstance service) {
  return true;
}

class ObdApp extends StatelessWidget {
  const ObdApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AppOBD2',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A0A0A),
        colorScheme: ColorScheme.dark(
          primary: const Color(0xFFFF3B30),
          secondary: const Color(0xFFFF9500),
          surface: const Color(0xFF1A1A1A),
          brightness: Brightness.dark,
        ),
      ),
      home: const DashboardPage(),
    );
  }
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final _obd = ObdService();
  List<BluetoothDevice> _bonded = [];
  BluetoothDevice? _selected;
  Timer? _poll;
  final Map<String, double?> _values = {for (final p in kDefaultPids) p.pid: null};
  bool _polling = false;
  String _log = '';

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _refreshBonded();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _obd.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  void _addLog(String s) => setState(() => _log = '$s\n$_log');

  Future<void> _refreshBonded() async {
    await [Permission.bluetooth, Permission.bluetoothScan, Permission.bluetoothConnect, Permission.location, Permission.notification].request();
    try {
      final list = await _obd.bondedDevices();
      final prefs = await SharedPreferences.getInstance();
      final lastAddr = prefs.getString('last_obd_addr');
      BluetoothDevice? pick;
      for (final d in list) {
        if (d.address == lastAddr) pick = d;
      }
      setState(() {
        _bonded = list;
        _selected = pick ?? (list.isNotEmpty ? list.first : null);
      });
      if (list.isEmpty) _addLog('No paired devices - pair ELM327 in system BT settings first');
    } catch (e) {
      _addLog('BT error: $e');
    }
  }

  Future<void> _connect() async {
    final dev = _selected;
    if (dev == null) return;
    setState(() => _obd.statusMsg = 'Connecting...');
    try {
      await _obd.connect(dev);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_obd_addr', dev.address);
      _addLog('Connected to ${dev.name ?? dev.address}');
      // เปิด foreground service กัน Android kill
      await FlutterBackgroundService().startService();
      _startPoll();
    } catch (e) {
      _addLog('Connect failed: $e');
    }
    setState(() {});
  }

  void _startPoll() {
    _poll?.cancel();
    _polling = true;
    var idx = 0;
    _poll = Timer.periodic(const Duration(milliseconds: 400), (_) async {
      if (_obd.state != ObdConnState.connected || !_polling) return;
      final pid = kDefaultPids[idx % kDefaultPids.length];
      idx++;
      final v = await _obd.readPid(pid);
      if (!mounted) return;
      setState(() => _values[pid.pid] = v);
    });
    setState(() {});
  }

  void _disconnect() {
    _poll?.cancel();
    _polling = false;
    _obd.disconnect();
    // ปิด foreground service
    FlutterBackgroundService().invoke('stop');
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final connected = _obd.state == ObdConnState.connected;
    final rpm = _values['010C'] ?? 0;
    final speed = _values['010D'] ?? 0;
    final load = _values['0104'] ?? 0;
    final coolant = _values['0105'] ?? 0;
    final intake = _values['010F'] ?? 0;
    final throttle = _values['0111'] ?? 0;
    final fuel = _values['012F'] ?? 0;
    final battery = _values['0142'] ?? 0;
    return Scaffold(
      appBar: AppBar(
        title: const Text('AppOBD2'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refreshBonded, tooltip: 'Refresh'),
          IconButton(icon: const Icon(Icons.bluetooth), onPressed: _obd.openBluetoothSettings, tooltip: 'BT settings'),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              border: Border(bottom: BorderSide(color: Colors.grey.shade900)),
            ),
            child: Row(
              children: [
                Icon(
                  connected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                  color: connected ? const Color(0xFFFF3B30) : Colors.grey,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _obd.statusMsg,
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_bonded.isNotEmpty) ...[
                  DropdownButton<BluetoothDevice>(
                    value: _bonded.contains(_selected) ? _selected : null,
                    hint: const Text('Select', style: TextStyle(fontSize: 12)),
                    underline: const SizedBox(),
                    isDense: true,
                    items: _bonded.map((d) => DropdownMenuItem(
                      value: d,
                      child: Text('${d.name ?? 'Unknown'}', style: const TextStyle(fontSize: 12)),
                    )).toList(),
                    onChanged: connected ? null : (d) => setState(() => _selected = d),
                  ),
                  const SizedBox(width: 8),
                ],
                ElevatedButton(
                  onPressed: connected ? _disconnect : _connect,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: connected ? Colors.grey.shade800 : const Color(0xFFFF3B30),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    minimumSize: Size.zero,
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                  child: Text(connected ? 'Disconnect' : 'Connect'),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      SupercarGauge(
                        label: 'RPM',
                        unit: 'x1000',
                        value: rpm / 1000,
                        maxValue: 8,
                        divisions: 8,
                        color: const Color(0xFFFF3B30),
                      ),
                      SupercarGauge(
                        label: 'SPEED',
                        unit: 'km/h',
                        value: speed,
                        maxValue: 260,
                        divisions: 10,
                        color: const Color(0xFFFF9500),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      _buildInfoCard('ENGINE LOAD', '${load.toStringAsFixed(0)}%', Icons.engineering),
                      _buildInfoCard('COOLANT', '${coolant.toStringAsFixed(0)}°C', Icons.thermostat),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _buildInfoCard('INTAKE', '${intake.toStringAsFixed(0)}°C', Icons.air),
                      _buildInfoCard('THROTTLE', '${throttle.toStringAsFixed(0)}%', Icons.speed),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _buildInfoCard('FUEL', '${fuel.toStringAsFixed(0)}%', Icons.local_gas_station),
                      _buildInfoCard('BATTERY', '${battery.toStringAsFixed(1)}V', Icons.battery_charging_full),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(String label, String value, IconData icon) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade900),
        ),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFFFF9500), size: 20),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: Colors.grey.shade500, fontSize: 10, letterSpacing: 1)),
                Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
