import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial_plus/flutter_bluetooth_serial_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'obd_pids.dart';
import 'obd_service.dart';

void main() => runApp(const ObdApp());

class ObdApp extends StatelessWidget {
  const ObdApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AppOBD2',
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.cyan, brightness: Brightness.dark),
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
    await [Permission.bluetooth, Permission.bluetoothScan, Permission.bluetoothConnect, Permission.location].request();
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
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final connected = _obd.state == ObdConnState.connected;
    return Scaffold(
      appBar: AppBar(
        title: const Text('AppOBD2'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refreshBonded, tooltip: 'Refresh'),
          IconButton(icon: const Icon(Icons.bluetooth), onPressed: _obd.openBluetoothSettings, tooltip: 'BT settings'),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('ELM327 Adapter', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    DropdownButton<BluetoothDevice>(
                      value: _bonded.contains(_selected) ? _selected : null,
                      hint: const Text('Select paired device'),
                      isExpanded: true,
                      items: _bonded.map((d) => DropdownMenuItem(value: d, child: Text('${d.name ?? 'Unknown'} (${d.address})'))).toList(),
                      onChanged: connected ? null : (d) => setState(() => _selected = d),
                    ),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(child: ElevatedButton.icon(onPressed: connected ? null : _connect, icon: const Icon(Icons.link), label: const Text('Connect'))),
                      const SizedBox(width: 8),
                      Expanded(child: OutlinedButton.icon(onPressed: connected ? _disconnect : null, icon: const Icon(Icons.link_off), label: const Text('Disconnect'))),
                    ]),
                    const SizedBox(height: 4),
                    Text(_obd.statusMsg, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: 1.6, crossAxisSpacing: 8, mainAxisSpacing: 8),
              itemCount: kDefaultPids.length,
              itemBuilder: (ctx, i) {
                final pid = kDefaultPids[i];
                final v = _values[pid.pid];
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(pid.name, style: Theme.of(context).textTheme.labelMedium),
                        const SizedBox(height: 4),
                        Text(v == null ? '--' : _fmt(pid, v), style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.cyanAccent, fontWeight: FontWeight.bold)),
                        Text(pid.unit, style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Log', style: TextStyle(fontWeight: FontWeight.bold)), const SizedBox(height: 4), Text(_log.isEmpty ? '(empty)' : _log, style: const TextStyle(fontFamily: 'monospace', fontSize: 11))]))),
          ],
        ),
      ),
    );
  }

  String _fmt(ObdPid pid, double v) {
    if (pid.unit == 'rpm' || pid.unit == 'km/h') return v.toStringAsFixed(0);
    if (pid.unit == 'V') return v.toStringAsFixed(1);
    return v.toStringAsFixed(1);
  }
}
