import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  final StepDatabase _db = StepDatabase.instance;

  @override
  void initState() {
    super.initState();
    _loadInfo();
  }

  Future<void> _loadInfo() async {
    setState(() => _loading = true);
    final prefs = await SharedPreferences.getInstance();
    _pairedId = prefs.getString('paired_device_id');
    _pairedName = prefs.getString('device_${_pairedId}_name');
    _connected = DeviceSyncService.instance.isConnected;
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
    await DeviceSyncService.instance.unpair();
    final prefs = await SharedPreferences.getInstance();
    if (_pairedId != null) {
      await prefs.remove('device_${_pairedId}_name');
    }
    await prefs.remove('paired_device_id');
    await _loadInfo();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connected devices'),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        onRefresh: _loadInfo,
        child: _loading
            ? ListView(children: const [SizedBox(height: 200), Center(child: CircularProgressIndicator())])
            : _pairedId == null
                ? ListView(children: const [Center(child: Padding(padding: EdgeInsets.all(24), child: Text('No paired device')))])
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      ListTile(
                        leading: const Icon(Icons.watch, color: Colors.greenAccent),
                        title: Text(_pairedName ?? _pairedId!),
                        subtitle: Text(_pairedName != null ? _pairedId! : _pairedId!),
                        trailing: _connected ? const Chip(label: Text('Connected')) : const Chip(label: Text('Disconnected')),
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
                          subtitle: Text(_lastUpdated == null ? 'never' : _relativeMinutes(_lastUpdated)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _unpair,
                        icon: const Icon(Icons.link_off),
                        label: const Text('Unpair / Forget device'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                      ),
                    ],
                  ),
      ),
    );
  }
}