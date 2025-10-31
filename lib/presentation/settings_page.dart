import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/database/step_database.dart';
import '../services/device_sync_service.dart';
import '../utils/permissions_helper.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({Key? key}) : super(key: key);

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final StepDatabase _db = StepDatabase.instance;
  bool _exporting = false;

  final DeviceSyncService _deviceService = DeviceSyncService.instance;
  StreamSubscription<DiscoveredDevice>? _scanSub;
  List<DiscoveredDevice> _scanResults = [];
  bool _scanning = false;
  String? _pairedId;
  String? _pairedName;

  // User profile
  double? _heightCm;
  double? _weightKg;

  @override
  void initState() {
    super.initState();
    _loadPaired();
    _loadProfile();
    _deviceService.loadPaired();
  }

  Future<void> _loadProfile() async {
    final profile = await _db.getUserProfile();
    if (mounted) {
      setState(() {
        _heightCm = profile['heightCm'];
        _weightKg = profile['weightKg'];
      });
    }
  }

  Future<void> _editProfile() async {
    final heightController = TextEditingController(
      text: _heightCm?.toString() ?? '',
    );
    final weightController = TextEditingController(
      text: _weightKg?.toString() ?? '',
    );

    await showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Your Profile'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: heightController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Height (cm)',
                    hintText: 'Enter your height',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: weightController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Weight (kg)',
                    hintText: 'Enter your weight',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () async {
                  final height = double.tryParse(heightController.text);
                  final weight = double.tryParse(weightController.text);
                  if (height != null || weight != null) {
                    await _db.saveUserProfile(
                      heightCm: height,
                      weightKg: weight,
                    );
                    await _loadProfile();
                  }
                  Navigator.pop(ctx);
                },
                child: const Text('Save'),
              ),
            ],
          ),
    );
  }

  Future<void> _loadPaired() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString('paired_device_id');
    final name = id == null ? null : prefs.getString('device_${id}_name');
    if (mounted) {
      setState(() {
        _pairedId = id;
        _pairedName = name;
      });
    }
  }

  Future<void> _startScan() async {
    final ok = await PermissionsHelper.ensureBlePermissions(context);
    if (!ok) return;

    await _stopScan();
    setState(() {
      _scanResults = [];
      _scanning = true;
    });

    _deviceService.startScan();
    _scanSub = _deviceService.scanResults.listen((dev) {
      if (mounted && !_scanResults.any((d) => d.id == dev.id)) {
        setState(() => _scanResults.add(dev));
      }
    });
  }

  Future<void> _stopScan() async {
    await _scanSub?.cancel();
    _scanSub = null;
    _deviceService.stopScan();
    if (mounted) {
      setState(() => _scanning = false);
    }
  }

  Future<void> _pairWith(DiscoveredDevice dev) async {
    await _stopScan();
    final deviceName = dev.name.isNotEmpty ? dev.name : dev.id;
    await _deviceService.connectTo(dev.id, deviceName: deviceName);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('device_${dev.id}_name', deviceName);
    await prefs.setString('paired_device_id', dev.id);
    if (mounted) {
      setState(() {
        _pairedId = dev.id;
        _pairedName = dev.name.isNotEmpty ? dev.name : null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Paired: ${dev.name.isNotEmpty ? dev.name : dev.id}'),
        ),
      );
    }
  }

  Future<void> _unpair() async {
    // fully forget the device and stop auto-connect
    await _deviceService.unpair();
    final prefs = await SharedPreferences.getInstance();
    if (_pairedId != null) {
      await prefs.remove('device_${_pairedId}_name');
    }
    await prefs.remove('paired_device_id');
    if (mounted) {
      setState(() {
        _pairedId = null;
        _pairedName = null;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Unpaired')));
    }
  }

  Future<void> _export() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final File? f = await _db.exportBackup();
      if (mounted) {
        if (f != null) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Backup saved: ${f.path}')));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Backup failed or no DB present')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export error: $e')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          ListTile(
            leading: const Icon(Icons.person, color: Colors.greenAccent),
            title: const Text('Your Profile'),
            subtitle: Text(
              _heightCm != null || _weightKg != null
                  ? 'Height: ${_heightCm?.toStringAsFixed(0) ?? 'Not set'} cm, Weight: ${_weightKg?.toStringAsFixed(1) ?? 'Not set'} kg'
                  : 'Set your height and weight',
            ),
            trailing: const Icon(Icons.edit),
            onTap: _editProfile,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.backup, color: Colors.greenAccent),
            title: const Text('Export backup'),
            subtitle: const Text('Save DB copy to device storage'),
            trailing:
                _exporting
                    ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(),
                    )
                    : null,
            onTap: _export,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.watch, color: Colors.greenAccent),
            title: const Text('Wearable / external device'),
            subtitle: Text(
              _pairedName ?? (_pairedId == null ? 'Not paired' : _pairedId!),
            ),
            trailing:
                _pairedId == null
                    ? TextButton(
                      onPressed: _scanning ? _stopScan : _startScan,
                      child: Text(_scanning ? 'Stop' : 'Scan'),
                    )
                    : TextButton(
                      onPressed: _unpair,
                      child: const Text('Unpair'),
                    ),
          ),
          if (_scanning)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                _scanResults.isEmpty ? 'Scanning...' : 'Tap a device to pair',
                style: const TextStyle(color: Colors.grey),
              ),
            ),
          if (_scanning && _scanResults.isNotEmpty)
            ..._scanResults.map(
              (d) => ListTile(
                title: Text(d.name.isNotEmpty ? d.name : d.id),
                subtitle: Text(d.id),
                onTap: () => _pairWith(d),
              ),
            ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.info, color: Colors.greenAccent),
            title: const Text('About'),
            subtitle: const Text('Step Tracker — local history & backup'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    super.dispose();
  }
}
