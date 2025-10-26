import 'dart:async';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:pedometer/pedometer.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import '../data/database/step_database.dart';
import '../services/device_sync_service.dart';

// --- Step Conversion Constants ---
const double _AVERAGE_STRIDE_LENGTH_M = 0.762; // meters
const double _CALORIES_PER_STEP = 0.04;

// Entry point for foreground task (must be top-level)
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(StepForegroundTaskHandler());
}

class StepForegroundTaskHandler extends TaskHandler {
  StreamSubscription<StepCount>? _stepCountSubscription;
  Timer? _notificationThrottle;
  Timer? _syncTimer;
  Timer? _notificationTimer;

  // State
  int _dailyStepCount = 0;
  int _stepsAtMidnight = 0;
  String _currentDate = '';

  // Utility
  String _getTodayDate() => DateFormat('yyyy-MM-dd').format(DateTime.now());

  double _calculateDistance(int steps) => steps * _AVERAGE_STRIDE_LENGTH_M;
  double _calculateCalories(int steps) => steps * _CALORIES_PER_STEP;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter taskStarter) async {
    try {
      final today = _getTodayDate();
      _currentDate = today;

      // Load persisted baseline from DB
      final baseline = await StepDatabase.instance.getStepBaselineForDay(today);
      _stepsAtMidnight = baseline ?? 0;

      // Load current daily steps from DB (for UI/notification init)
      final session = await StepDatabase.instance.getSessionForDay(today);
      _dailyStepCount = session?['user_steps'] as int? ?? 0;

      // Initialize BLE
      await DeviceSyncService.instance.loadPaired();

      // Request necessary permissions
      await _requestPermissions();

      // Start pedometer with error handling
      _stepCountSubscription = Pedometer.stepCountStream.distinct().listen(
        _onStepEvent,
        onError: (error) {
          print('Pedometer error: $error');
          _updateNotification(
            title: 'Strido - Sensor Error',
            message: 'Please check step counter permissions',
          );
        },
        cancelOnError: false,
      );

      // Initial notification update
      await _updateNotificationWithSteps(_dailyStepCount);

      // Start periodic sync
      _startPeriodicSync();
    } catch (e) {
      print('Background service error: $e');
      rethrow;
    }
  }

  Future<void> _onStepEvent(StepCount event) async {
    try {
      final today = _getTodayDate();

      // Handle day rollover
      if (today != _currentDate) {
        // Save baseline for new day
        _currentDate = today;
        _stepsAtMidnight = event.steps;
        _dailyStepCount = 0;

        // Persist new baseline
        await StepDatabase.instance.setStepBaselineForDay(today, _stepsAtMidnight);
      }

      // Compute today's steps
      _dailyStepCount = event.steps - _stepsAtMidnight;
      if (_dailyStepCount < 0) _dailyStepCount = 0; // safety

      // Save to DB (you may debounce this if needed)
      final distance = _calculateDistance(_dailyStepCount);
      final calories = _calculateCalories(_dailyStepCount);
      await StepDatabase.instance.updateUserSteps(
        _currentDate,
        _dailyStepCount,
        calories,
        distance,
      );

      // Throttled notification update
      _throttledUpdateNotification();
    } catch (e) {
      print('Error in step event handler: $e');
      // Update notification to show error state
      await FlutterForegroundTask.updateService(
        notificationTitle: 'Strido - Error',
        notificationText: 'Error tracking steps. Please restart the app.',
      );
    }
  }

  void _throttledUpdateNotification() {
    if (_notificationThrottle?.isActive ?? false) {
      return; // Prevent multiple pending updates
    }
    if ((_dailyStepCount - (_notificationThrottle?.hashCode ?? 0)).abs() >= 10) {
      _notificationThrottle?.cancel();
      _notificationThrottle = Timer(const Duration(seconds: 2), () {
        FlutterForegroundTask.updateService(
          notificationTitle: 'Strido Step Tracker',
          notificationText: 'Current Steps: $_dailyStepCount',
        );
      });
    }
  }

  Future<void> _requestPermissions() async {
    try {
      // Request necessary permissions
      await Permission.activityRecognition.request();
      await Permission.notification.request();
    } catch (e) {
      print('Permission request error: $e');
    }
  }

  void _startPeriodicSync() {
    // Cancel existing timers if any
    _syncTimer?.cancel();
    _notificationTimer?.cancel();

    // Sync data every hour
    _syncTimer = Timer.periodic(const Duration(hours: 1), (_) async {
      await _syncData();
    });

    // Update notification more frequently (every 15 minutes)
    _notificationTimer = Timer.periodic(const Duration(minutes: 15), (_) {
      _updateNotificationWithSteps(_dailyStepCount);
    });
  }

  Future<void> _syncData() async {
    try {
      // Recalculate metrics
      final distance = _calculateDistance(_dailyStepCount);
      final calories = _calculateCalories(_dailyStepCount);

      // Update local database
      await StepDatabase.instance.updateUserSteps(
        _currentDate,
        _dailyStepCount,
        calories,
        distance,
      );

      // Sync with BLE device if connected
      if (DeviceSyncService.instance.isConnected) {
        await DeviceSyncService.instance.syncDataFromDevice();
      }

      // Update notification with sync time  
      await _updateNotificationWithSteps(_dailyStepCount);
    } catch (e) {
      print('Sync error: $e');
      await _updateNotification(
        title: 'Strido - Sync Error',
        message: 'Failed to sync steps: ${e.toString()}',
      );
    }
  }

  Future<void> _updateNotificationWithSteps(int steps, {DateTime? lastSync}) async {
    final calories = _calculateCalories(steps).toInt();
    final distance = _calculateDistance(steps);
    final syncTime = lastSync != null 
        ? '\nLast sync: ${DateFormat('h:mm a').format(lastSync)}' 
        : '';

    await FlutterForegroundTask.updateService(
      notificationTitle: 'Strido - $steps Steps',
      notificationText: '$calories cal • ${distance.toStringAsFixed(2)} m$syncTime',
    );
  }

  Future<void> _updateNotification({required String title, required String message}) async {
    await FlutterForegroundTask.updateService(
      notificationTitle: title,
      notificationText: message,
    );
  }

  @override
  void onRepeatEvent(DateTime timestamp) async {
    // Sync data on each repeat event (approximately every 15 minutes)
    await _syncData();
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool didCleanup) async {
    try {
      _notificationThrottle?.cancel();
      _syncTimer?.cancel();
      _notificationTimer?.cancel();
      await _stepCountSubscription?.cancel();
      await DeviceSyncService.instance.disconnect();
      
      // Make sure to persist the last known step count before stopping
      if (_dailyStepCount > 0) {
        final distance = _calculateDistance(_dailyStepCount);
        final calories = _calculateCalories(_dailyStepCount);
        await StepDatabase.instance.updateUserSteps(
          _currentDate,
          _dailyStepCount,
          calories,
          distance,
        );
      }
    } catch (e) {
      print('Error during cleanup: $e');
    }
  }
}