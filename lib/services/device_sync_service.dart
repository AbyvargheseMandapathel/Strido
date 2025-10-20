import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/database/step_database.dart';

class DeviceSyncService {
  DeviceSyncService._init();
  static final DeviceSyncService instance = DeviceSyncService._init();

  final _ble = FlutterReactiveBle();
  final StepDatabase _db = StepDatabase.instance;
  final _scanController = StreamController<DiscoveredDevice>.broadcast();
  Stream<DiscoveredDevice> get scanResults => _scanController.stream;

  // NEW: expose external-step events and connection state so UI/service can sync
  final _extStepsController = StreamController<int>.broadcast();
  Stream<int> get externalStepStream => _extStepsController.stream;

  final _connStateController = StreamController<bool>.broadcast();
  Stream<bool> get connectionStateStream => _connStateController.stream;

  StreamSubscription<DiscoveredDevice>? _scanSub;
  StreamSubscription<ConnectionStateUpdate>? _connSub;
  StreamSubscription<List<int>>? _notifySub;

  String? _connectedDeviceId;
  bool get isConnected => _connectedDeviceId != null;

  // Known fallback/default UUIDs (kept as examples). We'll try dynamic discovery first,
  // but these are used as fallback attempts.
  final String defaultServiceUuid = '0000fff0-0000-1000-8000-00805f9b34fb';
  final String defaultCharacteristicUuid = '0000fff1-0000-1000-8000-00805f9b34fb';

  // Helper: consistent yyyy-MM-dd for today's sessions and per-day keys
  String _todayKey() => DateTime.now().toIso8601String().substring(0, 10);

  /// Start scanning. If withServiceUuids is null or empty we scan *all* devices
  /// (recommended) — caller can provide filters for narrower scans.
  Future<void> startScan({List<String>? withServiceUuids}) async {
    stopScan();

    List<Uuid>? services;
    if (withServiceUuids != null && withServiceUuids.isNotEmpty) {
      services = withServiceUuids.map((s) {
        try {
          return Uuid.parse(s);
        } catch (_) {
          return Uuid.parse(defaultServiceUuid);
        }
      }).toList();
    } else {
      // null => scan for all devices (no service filter)
      services = null;
    }

    _scanSub = _ble.scanForDevices(
      withServices: services ?? const [],
      scanMode: ScanMode.balanced,
    ).listen(
      (device) {
        // forward discovered devices
        _scanController.add(device);
      },
      onError: (Object error) {
        debugPrint('BLE scan error: $error');
      },
      cancelOnError: false,
    );
  }

  void stopScan() {
    _scanSub?.cancel();
    _scanSub = null;
  }

  /// Connect to device and attempt to discover & subscribe.
  Future<void> connectTo(String deviceId) async {
    if (_connectedDeviceId == deviceId && isConnected) return;
    await disconnect();

    try {
      final connectStream = _ble.connectToDevice(
        id: deviceId,
        connectionTimeout: const Duration(seconds: 10),
      );

      _connSub = connectStream.listen(
        (event) async {
          if (event.connectionState == DeviceConnectionState.connected) {
            debugPrint('Connected to $deviceId');
            _connectedDeviceId = deviceId;
            _connStateController.add(true);
            await _savePairedDevice(deviceId);
            await _discoverAndSubscribe(deviceId);
          } else if (event.connectionState == DeviceConnectionState.disconnected) {
            debugPrint('Disconnected from $deviceId');
            _handleDisconnection();
            _connStateController.add(false);
          }
        },
        onError: (Object error) {
          debugPrint('Connection error ($deviceId): $error');
          _handleDisconnection();
          _connStateController.add(false);
        },
        cancelOnError: true,
      );
    } catch (e) {
      debugPrint('connectTo exception: $e');
    }
  }

  void _handleDisconnection() {
    _connectedDeviceId = null;
    _notifySub?.cancel();
    _notifySub = null;
  }

  /// Disconnect but keep saved pairing only if explicitly unpair called.
  Future<void> disconnect() async {
    try {
      await _connSub?.cancel();
    } catch (_) {}
    _connSub = null;

    try {
      await _notifySub?.cancel();
    } catch (_) {}
    _notifySub = null;

    final wasConnected = _connectedDeviceId != null;
    _connectedDeviceId = null;
    if (wasConnected) _connStateController.add(false);
    // keep persisted paired id unless explicit unpair()
  }

  Future<void> unpair() async {
    await disconnect();
    await _clearPairedDevice();
  }

  // Discover services/characteristics and subscribe to a suitable characteristic.
  // Strategy:
  // 1) Try any saved service/char for this device (prefs).
  // 2) Discover services and subscribe to characteristics supporting notify/indicate.
  // 3) For each candidate characteristic we subscribe briefly and wait for a parsable step payload.
  // 4) If found, persist the UUIDs for next time.
  Future<void> _discoverAndSubscribe(String deviceId) async {
    // cancel any previous notify
    _notifySub?.cancel();
    _notifySub = null;

    final prefs = await SharedPreferences.getInstance();

    // 1) try saved mapping (if any)
    final savedSvc = prefs.getString('device_${deviceId}_svc');
    final savedChar = prefs.getString('device_${deviceId}_char');
    if (savedSvc != null && savedChar != null) {
      debugPrint('Trying saved mapping for $deviceId: $savedSvc / $savedChar');
      final ok = await _trySubscribe(deviceId, savedSvc, savedChar);
      if (ok) return;
      debugPrint('Saved mapping failed for $deviceId, falling back to discovery');
    }

    // 2) discover services (best-effort; some devices/platforms may not return services)
    List<DiscoveredService> services = [];
    try {
      services = await _ble.discoverServices(deviceId);
    } catch (e) {
      debugPrint('Service discovery failed for $deviceId: $e');
      services = [];
    }

    final List<Map<String, String>> candidates = [];

    for (final svc in services) {
      for (final ch in svc.characteristics) {
        final svcId = svc.serviceId.toString();
        final chId = ch.characteristicId.toString();
        candidates.add({'svc': svcId, 'char': chId, 'props': _propsString(ch)});
      }
    }

    // Prioritize notify/indicate properties
    candidates.sort((a, b) {
      final ai = (a['props']!.contains('notify') || a['props']!.contains('indicate')) ? 0 : 1;
      final bi = (b['props']!.contains('notify') || b['props']!.contains('indicate')) ? 0 : 1;
      return ai - bi;
    });

    // If discovery returned nothing, include fallback candidate(s)
    if (candidates.isEmpty) {
      candidates.add({'svc': defaultServiceUuid, 'char': defaultCharacteristicUuid, 'props': 'fallback'});
      debugPrint('No characteristics discovered; trying fallback UUIDs for $deviceId');
    }

    for (final c in candidates) {
      final svcId = c['svc']!;
      final chId = c['char']!;
      debugPrint('Trying candidate $svcId / $chId for $deviceId (props=${c['props']})');
      final ok = await _trySubscribe(deviceId, svcId, chId);
      if (ok) {
        // persist mapping
        try {
          await prefs.setString('device_${deviceId}_svc', svcId);
          await prefs.setString('device_${deviceId}_char', chId);
        } catch (e) {
          debugPrint('Failed to persist mapping for $deviceId: $e');
        }
        debugPrint('Subscribed to $svcId / $chId for $deviceId');
        return;
      }
    }

    debugPrint('No usable characteristic found for $deviceId');
  }

  String _propsString(DiscoveredCharacteristic ch) {
    final props = <String>[];
    if (ch.isReadable) props.add('read');
    if (ch.isWritableWithResponse) props.add('writeResp');
    if (ch.isWritableWithoutResponse) props.add('writeNoResp');
    if (ch.isNotifiable) props.add('notify');
    if (ch.isIndicatable) props.add('indicate');
    return props.join(',');
  }

  // Try to subscribe to a single characteristic and validate data for a short window.
  // Returns true if subscription produced a valid steps payload.
  Future<bool> _trySubscribe(String deviceId, String serviceUuid, String charUuid) async {
    QualifiedCharacteristic qc;
    try {
      qc = QualifiedCharacteristic(
        serviceId: Uuid.parse(serviceUuid),
        characteristicId: Uuid.parse(charUuid),
        deviceId: deviceId,
      );
    } catch (e) {
      debugPrint('Invalid UUIDs: $serviceUuid / $charUuid -> $e');
      return false;
    }

    await _notifySub?.cancel();
    _notifySub = null;

    final completer = Completer<bool>();
    StreamSubscription<List<int>>? testSub;

    try {
      final stream = _ble.subscribeToCharacteristic(qc);
      testSub = stream.listen((data) async {
        final parsed = _parseStepData(data);
        if (parsed != null && parsed >= 0) {
          // keep this sub as the active subscription
          _notifySub = testSub;
          if (!completer.isCompleted) completer.complete(true);

          // --- NEW: delta-based merging per-device (scoped by date) ---
          try {
            final prefs = await SharedPreferences.getInstance();
            final today = _todayKey();
            final keyLast = 'device_${deviceId}_last_total_$today';
            final int? lastTotal = prefs.getInt(keyLast);

            int delta;
            if (lastTotal == null) {
              // first time we see this device today.
              // Treat first reported value as additive contribution by default.
              delta = parsed;
            } else {
              delta = parsed - lastTotal;
              if (delta < 0) {
                // device counter likely reset/restarted — treat current reading as new contribution
                delta = parsed;
              }
            }

            // persist lastTotal for next time (date-scoped)
            await prefs.setInt(keyLast, parsed);

            // merge delta into today's session
            final todayDate = _todayKey();
            final session = await _db.getSessionForDay(todayDate);

            if (session == null) {
              // create session with delta as initial user_steps; leave system_base at 0 so phone sensor can still work
              await _db.saveSession(todayDate, 0, delta, calories: 0.0, distanceMeters: delta * 0.78);
            } else {
              final currentUser = (session['user_steps'] as int?) ?? 0;
              final newUser = (currentUser + delta).clamp(0, 1 << 30);
              final calories = session['calories'] as double? ?? 0.0;
              final distance = session['distance_m'] as double? ?? (newUser * 0.78);
              await _db.updateUserSteps(todayDate, newUser, calories, distance);
            }

            // emit external steps so UI updates immediately
            final updatedUser = (session == null) ? delta : ((session['user_steps'] as int? ?? 0) + delta);
            _extStepsController.add(updatedUser);
          } catch (e) {
            debugPrint('DB merge error from device $deviceId: $e');
          }
        }
      }, onError: (e) {
        debugPrint('subscribe error on $serviceUuid/$charUuid: $e');
      }, cancelOnError: true);

      // Wait up to 3 seconds for a valid payload
      Future.delayed(const Duration(seconds: 3)).then((_) {
        if (!completer.isCompleted) completer.complete(false);
      });

      final result = await completer.future;
      if (!result) {
        await testSub?.cancel();
        return false;
      }

      return true;
    } catch (e) {
      debugPrint('Error while trying to subscribe $serviceUuid/$charUuid: $e');
      try {
        await testSub?.cancel();
      } catch (_) {}
      return false;
    }
  }

  int? _parseStepData(List<int> rawData) {
    if (rawData.isEmpty) return null;

    // Try UTF-8 string first (some devices send text)
    try {
      final text = utf8.decode(rawData);
      final parsed = int.tryParse(text.trim());
      if (parsed != null && parsed >= 0) return parsed;
    } catch (_) {}

    // Binary formats: little-endian ints
    final bytes = Uint8List.fromList(rawData);
    try {
      if (bytes.length >= 4) {
        final data = ByteData.sublistView(bytes);
        return data.getUint32(0, Endian.little);
      } else if (bytes.length >= 2) {
        final data = ByteData.sublistView(bytes);
        return data.getUint16(0, Endian.little);
      } else if (bytes.isNotEmpty) {
        return bytes[0];
      }
    } catch (_) {}

    return null;
  }

  Future<void> loadPaired() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString('paired_device_id');
    if (id != null && !kIsWeb) {
      // attempt auto-connect but don't throw on failure
      try {
        await connectTo(id);
      } catch (e) {
        debugPrint('Auto-connect failed for $id: $e');
      }
    }
  }

  Future<void> _savePairedDevice(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('paired_device_id', id);
  }

  Future<void> _clearPairedDevice() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('paired_device_id');
    // also clear per-day last_total keys for today to avoid leftovers
    final today = _todayKey();
    final keys = prefs.getKeys().where((k) => k.startsWith('device_') && k.endsWith('_$today')).toList();
    for (final k in keys) {
      await prefs.remove(k);
    }
  }

  void dispose() {
    stopScan();
    _scanController.close();
    _extStepsController.close();
    _connStateController.close();
    disconnect();
  }
}