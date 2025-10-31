import 'dart:async';
import 'package:flutter/material.dart';
import '../data/database/step_database.dart';
import '../services/device_sync_service.dart';

class ConnectedDevicesPage extends StatefulWidget {
  const ConnectedDevicesPage({Key? key}) : super(key: key);

  @override
  State<ConnectedDevicesPage> createState() => _ConnectedDevicesPageState();
}

class _ConnectedDevicesPageState extends State<ConnectedDevicesPage> {
  String? _pairedId;
  String? _pairedName;
  bool _connected = false;
  int _steps = 0;
  String? _lastUpdated;
  bool _loading = true;
  List<Map<String, String>> _pairedDevices = [];

  final StepDatabase _db = StepDatabase.instance;
  final DeviceSyncService _deviceService = DeviceSyncService.instance;

  @override
  void initState() {
    super.initState();
    _loadInfo();
  }

  Future<void> _loadInfo() async {
    setState(() => _loading = true);

    // Load connected device info if any
    final connectedDevice = await _deviceService.getConnectedDeviceInfo();
    _connected = connectedDevice != null;
    _pairedId = connectedDevice?['id'];
    _pairedName = connectedDevice?['name'];

    // Load paired devices history
    _pairedDevices = await _deviceService.getPairedDevices();

    // Load step data for connected device
    if (_pairedId != null) {
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final session = await _db.getSessionForDay(today);
      if (session != null) {
        _steps = session['user_steps'] as int? ?? 0;
        _lastUpdated = session['last_updated'] as String?;
      } else {
        _steps = 0;
        _lastUpdated = null;
      }
    }

    if (mounted) setState(() => _loading = false);
  }

  String _relativeMinutes(String? iso) {
    if (iso == null) return 'never';
    try {
      final dt = DateTime.parse(iso);
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return 'just now';
      if (diff.inMinutes == 1) return '1 minute ago';
      return '${diff.inMinutes} minutes ago';
    } catch (_) {
      return iso;
    }
  }

  Future<void> _unpair() async {
    await _deviceService.unpair();
    await _loadInfo();
  }

  Future<void> _connectToDevice(String deviceId, String deviceName) async {
    try {
      await _deviceService.connectTo(deviceId, deviceName: deviceName);
      await _loadInfo();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to connect: $e')));
      }
    }
  }

  List<Widget> _buildConnectedDeviceSection() {
    return [
      ListTile(
        leading: const Icon(Icons.watch, color: Colors.greenAccent),
        title: Text(_pairedName ?? _pairedId!),
        subtitle: Text(_pairedName != null ? _pairedId! : _pairedId!),
        trailing:
            _connected
                ? const Chip(label: Text('Connected'))
                : const Chip(label: Text('Disconnected')),
      ),
      const SizedBox(height: 12),
      Card(
        child: ListTile(
          title: const Text('Steps reported (today)'),
          subtitle: Text('$_steps steps'),
        ),
      ),
      const SizedBox(height: 8),
      Card(
        child: ListTile(
          title: const Text('Last DB update'),
          subtitle: Text(
            _lastUpdated == null ? 'never' : _relativeMinutes(_lastUpdated),
          ),
        ),
      ),
      const SizedBox(height: 16),
      ElevatedButton.icon(
        onPressed: _unpair,
        icon: const Icon(Icons.link_off),
        label: const Text('Unpair / Forget device'),
        style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
      ),
    ];
  }

  List<Widget> _buildPairedDevicesSection() {
    return [
      const Text('Paired devices history:'),
      const SizedBox(height: 8),
      ..._pairedDevices.map((device) {
        return ListTile(
          title: Text(device['name'] ?? device['id'] ?? ''),
          subtitle: Text(device['id'] ?? ''),
          trailing: ElevatedButton(
            onPressed:
                () =>
                    _connectToDevice(device['id'] ?? '', device['name'] ?? ''),
            child: const Text('Connect'),
          ),
        );
      }).toList(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Connected devices'), centerTitle: true),
      body: RefreshIndicator(
        onRefresh: _loadInfo,
        child:
            _loading
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Connected Device Section
                      if (_pairedId != null) ..._buildConnectedDeviceSection(),

                      // Paired Devices History Section
                      if (_pairedDevices.isNotEmpty)
                        ..._buildPairedDevicesSection(),

                      // No devices paired state
                      if (_pairedDevices.isEmpty && _pairedId == null)
                        const Padding(
                          padding: EdgeInsets.all(24.0),
                          child: Center(child: Text('No devices paired yet')),
                        ),
                    ],
                  ),
                ),
      ),
    );
  }
}
