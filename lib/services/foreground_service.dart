import 'dart:async';
import 'package:workmanager/workmanager.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'notification_service.dart';
import 'device_sync_service.dart';
import '../data/database/step_database.dart';

class ForegroundService {
  static const String _tag = 'ForegroundService';
  static const String _workTag = 'strido_step_sync_work';
  static const Duration _syncInterval = Duration(hours: 1);
  static Timer? _watchdogTimer;
  static Timer? _notificationUpdateTimer;

  // Initialize the foreground service and background work
  static Future<void> initialize() async {
    try {
      // Initialize notification service
      await NotificationService.init();
      
      // Request necessary permissions
      await _requestPermissions();
      
      // Initialize WorkManager for periodic background tasks
      await Workmanager().initialize(
        callbackDispatcher,
        isInDebugMode: kDebugMode,
      );
      
      // Register periodic background sync
      await _registerBackgroundSync();
      
      // Start the foreground service
      await start();
      
      // Start watchdog to ensure service stays alive
      _startWatchdog();
      
      // Start notification update timer
      _startNotificationUpdater();
      
      debugPrint('[$_tag] Service initialized successfully');
    } catch (e) {
      debugPrint('[$_tag] Error initializing service: $e');
      rethrow;
    }
  }
  
  // Start the foreground service
  static Future<void> start() async {
    try {
      // Show persistent notification
      await NotificationService.showForegroundNotification(
        title: 'Strido is Running',
        message: 'Tracking your steps 24/7',
        isPersistent: true,
      );
      
      debugPrint('[$_tag] Foreground service started');
    } catch (e) {
      debugPrint('[$_tag] Error starting foreground service: $e');
      rethrow;
    }
  }
  
  // Stop the foreground service
  static Future<void> stop() async {
    try {
      _watchdogTimer?.cancel();
      _notificationUpdateTimer?.cancel();
      await NotificationService.cancelForegroundNotification();
      debugPrint('[$_tag] Foreground service stopped');
    } catch (e) {
      debugPrint('[$_tag] Error stopping foreground service: $e');
    }
  }
  
  // Update notification with current step data
  static void _updateNotificationWithCurrentData() async {
    try {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final session = await StepDatabase.instance.getSessionForDay(today);
      
      if (session != null) {
        final steps = session['user_steps'] as int? ?? 0;
        final calories = session['calories'] as double? ?? 0.0;
        final distance = session['distance_m'] as double? ?? 0.0;
        final lastUpdated = session['last_updated'] as String?;
        
        DateTime? lastSync;
        if (lastUpdated != null) {
          try {
            lastSync = DateTime.parse(lastUpdated);
          } catch (e) {
            debugPrint('[$_tag] Error parsing last updated: $e');
          }
        }
        
        await NotificationService.updateNotificationWithData(
          steps: steps,
          calories: calories.toInt(),
          distance: distance,
          lastSync: lastSync,
        );
      }
    } catch (e) {
      debugPrint('[$_tag] Error updating notification: $e');
    }
  }
  
  // Start notification updater
  static void _startNotificationUpdater() {
    _notificationUpdateTimer?.cancel();
    
    // Update immediately
    _updateNotificationWithCurrentData();
    
    // Then update every hour
    _notificationUpdateTimer = Timer.periodic(
      const Duration(hours: 1),
      (_) => _updateNotificationWithCurrentData(),
    );
    
    debugPrint('[$_tag] Started notification updater');
  }
  
  // Register periodic background sync with WorkManager
  static Future<void> _registerBackgroundSync() async {
    try {
      // Cancel any existing work
      await Workmanager().cancelByTag(_workTag);
      
      // Register new periodic work with best settings for 24/7 operation
      await Workmanager().registerPeriodicTask(
        _workTag,
        'strido_step_sync',
        frequency: _syncInterval,
        constraints: Constraints(
          networkType: NetworkType.not_required, // Don't require network
          requiresBatteryNotLow: false,
          requiresCharging: false,
          requiresDeviceIdle: false,
          requiresStorageNotLow: false,
        ),
        initialDelay: const Duration(minutes: 1), // First run after 1 minute
        existingWorkPolicy: ExistingWorkPolicy.replace, // Replace existing work
      );
      
      debugPrint('[$_tag] Registered background sync every ${_syncInterval.inHours} hours');
    } catch (e) {
      debugPrint('[$_tag] Error registering background sync: $e');
      rethrow;
    }
  }
  
  // Background task callback
  @pragma('vm:entry-point')
  static void callbackDispatcher() {
    Workmanager().executeTask((task, inputData) async {
      try {
        debugPrint('[$_tag] Background sync started');
        
        // Initialize services
        await NotificationService.init();
        
        // Get today's data
        final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
        final session = await StepDatabase.instance.getSessionForDay(today);
        
        int steps = 0;
        double calories = 0.0;
        double distance = 0.0;
        
        if (session != null) {
          steps = session['user_steps'] as int? ?? 0;
          calories = (session['calories'] as double? ?? 0.0);
          distance = (session['distance_m'] as double? ?? 0.0);
        }
        
        // Update notification
        await NotificationService.updateNotificationWithData(
          steps: steps,
          calories: calories.toInt(),
          distance: distance,
          lastSync: DateTime.now(),
        );
        
        // Sync with BLE device if connected
        if (DeviceSyncService.instance.isConnected) {
          await DeviceSyncService.instance.syncDataFromDevice();
        }
        
        debugPrint('[$_tag] Background sync completed');
        return Future.value(true);
      } catch (e) {
        debugPrint('[$_tag] Error in background sync: $e');
        return Future.value(false);
      }
    });
  }
  
  // Start watchdog to ensure service stays alive
  static void _startWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(const Duration(minutes: 15), (timer) async {
      try {
        // Ensure notification is still showing
        if (!(await NotificationService.isForegroundServiceActive())) {
          debugPrint('[$_tag] Watchdog detected service not running, restarting...');
          await start();
        }
      } catch (e) {
        debugPrint('[$_tag] Watchdog error: $e');
      }
    });
  }
  
  // Request necessary permissions
  static Future<void> _requestPermissions() async {
    try {
      final statuses = await [
        Permission.activityRecognition,
        if (defaultTargetPlatform == TargetPlatform.android) ...{
          Permission.notification,
          Permission.ignoreBatteryOptimizations,
        },
      ].request();
      
      // Log permission statuses
      statuses.forEach((permission, status) {
        debugPrint('[$_tag] ${permission.toString()}: $status');
      });
      
      // Request to ignore battery optimizations
      if (defaultTargetPlatform == TargetPlatform.android) {
        await Permission.ignoreBatteryOptimizations.request();
      }
    } catch (e) {
      debugPrint('[$_tag] Error requesting permissions: $e');
    }
  }
}
