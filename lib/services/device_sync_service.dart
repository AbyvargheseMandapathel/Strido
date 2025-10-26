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

  /// Returns a list of all previously paired devices with their IDs and names
  Future<List<Map<String, String>>> getPairedDevices() async {
    final prefs = await SharedPreferences.getInstance();
    final pairedDevices = prefs.getStringList('paired_devices') ?? [];
    
    final List<Map<String, String>> devices = [];
    
    for (final deviceId in pairedDevices) {
      final deviceName = prefs.getString('device_${deviceId}_name') ?? 'Unknown Device';
      devices.add({
        'id': deviceId,
        'name': deviceName,
      });
    }
    
    return devices;
  }

  /// Returns the currently connected device info if any
  Future<Map<String, String>?> getConnectedDeviceInfo() async {
    if (_connectedDeviceId == null) return null;
    
    final prefs = await SharedPreferences.getInstance();
    final deviceName = prefs.getString('device_${_connectedDeviceId}_name') ?? 'Unknown Device';
    
    return {
      'id': _connectedDeviceId!,
      'name': deviceName,
    };
  }

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
  /// **UPDATED**: Accepts deviceName to save to persistence.
  Future<void> connectTo(String deviceId, {required String deviceName}) async {
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
            // Save both ID and Name
            await _savePairedDevice(deviceId, deviceName);
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

  // --- NEW: Hourly Sync Method for Background Task ---
  /// Attempts to read the step characteristic for hourly synchronization.
  /// This is called by the background service's onRepeatEvent.
  Future<void> syncDataFromDevice() async {
    final deviceId = _connectedDeviceId;
    if (deviceId == null) {
      debugPrint('DeviceSyncService: No active connection for hourly sync.');
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final savedSvc = prefs.getString('device_${deviceId}_svc');
    final savedChar = prefs.getString('device_${deviceId}_char');

    if (savedSvc == null || savedChar == null) {
      debugPrint('DeviceSyncService: No characteristic map for $deviceId, cannot sync.');
      return;
    }

    QualifiedCharacteristic qc;
    try {
      qc = QualifiedCharacteristic(
        serviceId: Uuid.parse(savedSvc),
        characteristicId: Uuid.parse(savedChar),
        deviceId: deviceId,
      );
    } catch (e) {
      debugPrint('DeviceSyncService: Invalid UUIDs during sync: $savedSvc / $savedChar -> $e');
      return;
    }

    try {
      // 1. Read the characteristic value directly
      final data = await _ble.readCharacteristic(qc);
      debugPrint('DeviceSyncService: Read data from $deviceId for sync: $data');

      // 2. Parse and merge the step data (reusing existing logic)
      final parsed = _parseStepData(data);
      if (parsed != null && parsed >= 0) {
        await _mergeExternalSteps(deviceId, parsed);
        debugPrint('DeviceSyncService: Successfully synced $parsed steps from $deviceId.');
      } else {
        debugPrint('DeviceSyncService: Read data could not be parsed as steps.');
      }
    } catch (e) {
      debugPrint('DeviceSyncService: Error reading characteristic for sync: $e');
      // If reading fails, simply return. The continuous subscription might still be running.
    }
  }
  // --- END NEW METHOD ---

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
          await _mergeExternalSteps(deviceId, parsed);
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
        await testSub.cancel();
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

  Future<void> _mergeExternalSteps(String deviceId, int parsedSteps) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final today = _todayKey();
      final keyLast = 'device_${deviceId}_last_total_$today';
      final int? lastTotal = prefs.getInt(keyLast);

      int delta;
      if (lastTotal == null) {
        // first time we see this device today.
        // Treat first reported value as additive contribution by default.
        delta = parsedSteps;
      } else {
        delta = parsedSteps - lastTotal;
        if (delta < 0) {
          // device counter likely reset/restarted — treat current reading as new contribution
          delta = parsedSteps;
        }
      }

      // persist lastTotal for next time (date-scoped)
      await prefs.setInt(keyLast, parsedSteps);

      // merge delta into today's session
      final todayDate = _todayKey();
      final session = await _db.getSessionForDay(todayDate);

      // Calculate new user steps and derived metrics
      final currentUser = (session?['user_steps'] as int?) ?? 0;
      final newUser = (currentUser + delta).clamp(0, 1 << 30);
      
      // Use average stride length (0.78m) and calorie estimate for derived fields
      final newDistance = newUser * 0.78; 
      final newCalories = newUser * 0.04;

      if (session == null) {
        // create session with delta as initial user_steps; leave system_base at 0
        await _db.saveSession(
          todayDate, 
          0, 
          newUser, 
          calories: newCalories, 
          distanceMeters: newDistance,
        );
      } else {
        await _db.updateUserSteps(
          todayDate, 
          newUser, 
          newCalories, 
          newDistance,
        );
      }

      // emit external steps so UI updates immediately
      _extStepsController.add(newUser);
    } catch (e) {
      debugPrint('DB merge error from device $deviceId: $e');
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
    final name = prefs.getString('paired_device_name');
    if (id != null && !kIsWeb) {
      // attempt auto-connect but don't throw on failure
      try {
        // Pass the retrieved name to connectTo, use id as fallback if name is null
        await connectTo(id, deviceName: name ?? id);
      } catch (e) {
        debugPrint('Auto-connect failed for $id: $e');
      }
    }
  }

  Future<void> _savePairedDevice(String deviceId, String deviceName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('paired_device_id', deviceId);
    await prefs.setString('paired_device_name', deviceName);
    
    // Add to paired devices list if not already there
    final pairedList = prefs.getStringList('paired_devices') ?? [];
    if (!pairedList.contains(deviceId)) {
      pairedList.add(deviceId);
      await prefs.setStringList('paired_devices', pairedList);
    }
    
    // Save device name
    await prefs.setString('device_${deviceId}_name', deviceName);
  }

  Future<void> _clearPairedDevice() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('paired_device_id');
    await prefs.remove('paired_device_name');
    // Note: We don't remove from paired_devices list to keep history
  }

  void dispose() {
    stopScan();
    _scanController.close();
    _extStepsController.close();
    _connStateController.close();
  }
}
