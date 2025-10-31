import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';
import '../data/database/step_database.dart';
import 'device_sync_service.dart';

class StepTrackerService {
  final StepDatabase _db = StepDatabase.instance;
  late final String _today;

  StreamSubscription<StepCount>? _stepSubscription;
  StreamSubscription<PedestrianStatus>? _statusSubscription;

  int _currentSteps = 0;
  int _systemBase = 0;
  String? _walkingStartTime;
  String? _walkingEndTime;
  bool _isWalking = false;

  final _stepsController = StreamController<int>.broadcast();
  final _statusController = StreamController<String>.broadcast();

  Stream<int> get stepStream => _stepsController.stream;
  Stream<String> get statusStream => _statusController.stream;
  StepDatabase get database => _db;

  double strideMeters = 0.78;
  double userWeightKg = 70.0;

  StepTrackerService() {
    _today = DateTime.now().toIso8601String().substring(0, 10);
  }

  void setUserParameters({double? strideMeters, double? weightKg}) {
    if (strideMeters != null) this.strideMeters = strideMeters;
    if (weightKg != null) this.userWeightKg = weightKg;
  }

  /// Requests activity recognition permission (Android) before initializing pedometer.
  Future<bool> requestStepPermission() async {
    if (kIsWeb || Platform.isIOS) return true;

    // Android only
    final status = await Permission.activityRecognition.status;
    if (status.isGranted) return true;

    if (status.isPermanentlyDenied) {
      debugPrint('Activity recognition permanently denied');
      return false;
    }

    final result = await Permission.activityRecognition.request();
    return result.isGranted;
  }

  Future<void> initialize() async {
    // Request permission first (Android)
    final hasPermission = await requestStepPermission();
    if (!hasPermission) {
      _statusController.add('PERMISSION_DENIED');
      return;
    }

    await _db.ensureRestored();

    final session = await _db.getSessionForDay(_today);
    if (session != null) {
      _systemBase = session['system_base_steps'] as int;
      _currentSteps = session['user_steps'] as int;
      _stepsController.add(_currentSteps);
    }

    // Start listening to step sensor
    _stepSubscription = Pedometer.stepCountStream.listen(
      _onStepCount,
      onError: _onStepError,
    );

    _statusSubscription = Pedometer.pedestrianStatusStream.listen(
      _onPedestrianStatus,
      onError: _onStatusError,
    );
  }

  void _onStepCount(StepCount event) {
    // Skip if BLE wearable is connected (it handles step counting)
    if (DeviceSyncService.instance.isConnected) return;

    final currentSystem = event.steps;

    // Initialize base on first event
    if (_systemBase == 0) {
      _systemBase = currentSystem;
      _walkingStartTime = DateTime.now().toIso8601String();
      _db.saveSession(
        _today,
        _systemBase,
        0,
        calories: 0.0,
        distanceMeters: 0.0,
        walkingStartTime: _walkingStartTime,
      );
    }

    // Calculate user steps (delta from base)
    final newSteps = (currentSystem - _systemBase).clamp(0, 1000000);

    // Track if walking started
    if (!_isWalking && newSteps > _currentSteps) {
      _isWalking = true;
      _walkingStartTime = DateTime.now().toIso8601String();
    }

    _currentSteps = newSteps;

    // Compute metrics
    final distanceMeters = calculateDistanceMeters(_currentSteps);
    final calories = calculateCalories(_currentSteps, userWeightKg);

    // ✅ Save to DB immediately — ensures no data loss if app is killed
    _db.updateUserSteps(_today, _currentSteps, calories, distanceMeters);

    // Notify UI
    _stepsController.add(_currentSteps);
  }

  void _onPedestrianStatus(PedestrianStatus status) {
    _statusController.add(status.status);

    // Simple tracking: record when we transition states
    if (_currentSteps > 0 && _walkingStartTime == null) {
      _walkingStartTime = DateTime.now().toIso8601String();
    }
  }

  void _onStepError(Object error) {
    debugPrint('Step sensor error: $error');
    _statusController.add('SENSOR_UNAVAILABLE');
  }

  void _onStatusError(Object error) {
    debugPrint('Pedestrian status error: $error');
    _statusController.add('SENSOR_ERROR');
  }

  Future<void> refresh() async {
    final session = await _db.getSessionForDay(_today);
    _currentSteps = session?['user_steps'] as int? ?? 0;
    _stepsController.add(_currentSteps);
  }

  Future<Map<String, Object?>?> getSession(String date) async {
    return _db.getSessionForDay(date);
  }

  Future<List<Map<String, Object?>>> getHistory() async {
    return _db.getAllSessions();
  }

  Future<int> getStepsForDate(String date) async {
    return _db.getStepsForDate(date);
  }

  double calculateDistanceMeters(int steps) {
    return steps * strideMeters;
  }

  double calculateCalories(int steps, double weightKg) {
    if (steps <= 0) return 0.0;
    final distanceKm = (steps * strideMeters) / 1000.0;
    final hours = distanceKm / 5.0; // assume 5 km/h walking speed
    const metWalking = 3.5;
    return (metWalking * weightKg * hours).toDouble();
  }

  void dispose() {
    _stepSubscription?.cancel();
    _statusSubscription?.cancel();
    _stepsController.close();
    _statusController.close();
  }
}
