import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';
import 'dart:developer' as developer;
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/material.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin
  _flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  static const String _channelId = 'strido_channel';
  static const String _channelName = 'Strido Tracker';
  static const String _channelDescription =
      'Tracks your steps in the background';

  // Check and request notification permissions (required for Android 13+)
  static Future<bool> checkAndRequestPermissions() async {
    try {
      if (!kIsWeb) {
        final plugin =
            _flutterLocalNotificationsPlugin
                .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin
                >();

        if (plugin == null) {
          developer.log('AndroidFlutterLocalNotificationsPlugin not available');
          return false;
        }

        // Check if notifications are enabled
        final bool? enabled = await plugin.areNotificationsEnabled();

        if (enabled != true) {
          // On Android 13+, we need to request the POST_NOTIFICATIONS permission
          if (defaultTargetPlatform == TargetPlatform.android) {
            // For Android 13+, we need to use the permission_handler package
            // Add this to your pubspec.yaml: permission_handler: ^10.4.0
            final status = await Permission.notification.status;
            if (status.isDenied) {
              final result = await Permission.notification.request();
              return result.isGranted;
            }
            return status.isGranted;
          }
        }

        return enabled ?? false;
      }
      return false;
    } catch (e) {
      developer.log('Error checking/requesting notification permissions: $e');
      return false;
    }
  }

  static const int _notificationId = 888;
  static bool _isForegroundServiceStarted = false;
  static const String _foregroundChannelId = 'strido_foreground_channel';
  static const String _foregroundChannelName = 'Strido Tracker Service';
  static const String _foregroundChannelDescription =
      'Keeps Strido running in the background to track your steps 24/7';

  static Future<void> init() async {
    try {
      developer.log('Initializing notification service...');

      // Check and request notification permissions for Android 13+
      final bool hasPermission = await checkAndRequestPermissions();
      developer.log('Notification permission granted: $hasPermission');

      // Initialize notification channel for Android 8.0+
      developer.log('Creating notification channels...');

      // Regular notifications channel
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDescription,
        importance: Importance.high,
        playSound: false,
        showBadge: true,
        enableVibration: false,
      );

      // Foreground service notification channel (required for Android 8.0+)
      const AndroidNotificationChannel foregroundChannel =
          AndroidNotificationChannel(
            _foregroundChannelId,
            _foregroundChannelName,
            description: _foregroundChannelDescription,
            importance: Importance.low,
            playSound: false,
            showBadge: false,
            enableVibration: false,
          );

      final androidPlugin =
          _flutterLocalNotificationsPlugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >();

      await androidPlugin?.createNotificationChannel(channel);
      await androidPlugin?.createNotificationChannel(foregroundChannel);

      developer.log('Notification channels created');

      // Initialize notification settings
      developer.log('Initializing notification settings...');
      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('ic_launcher');

      final DarwinInitializationSettings initializationSettingsIOS =
          DarwinInitializationSettings(
            requestSoundPermission: false,
            requestBadgePermission: false,
            requestAlertPermission: false,
          );

      await _flutterLocalNotificationsPlugin.initialize(
        InitializationSettings(
          android: initializationSettingsAndroid,
          iOS: initializationSettingsIOS,
        ),
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          developer.log('Notification tapped: ${response.payload}');
        },
      );
      developer.log('Notification service initialized successfully');
    } catch (e, stackTrace) {
      developer.log(
        'Error initializing notifications: $e',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Update notification with step data
  static Future<void> updateNotificationWithData({
    required int steps,
    required int calories,
    required double distance,
    DateTime? lastSync,
  }) async {
    try {
      final distanceKm = (distance / 1000).toStringAsFixed(2);

      String message;
      if (lastSync != null) {
        message = 'Stridio is running • $steps steps';
      } else {
        message = 'Stridio is running • $steps steps';
      }

      await showForegroundNotification(
        title: 'Strido Step Tracker',
        message: message,
        isPersistent: true,
      );
    } catch (e) {
      developer.log('Error updating notification with data: $e');
    }
  }

  static String _formatTime(DateTime time) {
    final hour =
        time.hour > 12
            ? time.hour - 12
            : time.hour == 0
            ? 12
            : time.hour;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  static Future<void> showForegroundNotification({
    required String title,
    required String message,
    String? payload,
    bool isPersistent = true,
  }) async {
    try {
      final androidDetails = AndroidNotificationDetails(
        isPersistent ? _foregroundChannelId : _channelId,
        isPersistent ? _foregroundChannelName : _channelName,
        channelDescription:
            isPersistent ? _foregroundChannelDescription : _channelDescription,
        importance: isPersistent ? Importance.low : Importance.high,
        priority: isPersistent ? Priority.low : Priority.high,
        ongoing: isPersistent,
        autoCancel: !isPersistent,
        showWhen: !isPersistent,
        enableVibration: false,
        playSound: false,
        channelShowBadge: !isPersistent,
        visibility: NotificationVisibility.public,
        // Ensure the notification can't be dismissed
        // ignore: deprecated_member_use
        onlyAlertOnce: true,
      );

      await _flutterLocalNotificationsPlugin.show(
        _notificationId,
        title,
        message,
        NotificationDetails(
          android: androidDetails,
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: false,
          ),
        ),
        payload: payload,
      );

      _isForegroundServiceStarted = isPersistent;

      if (isPersistent) {
        // Request to keep CPU on for background processing
        // This is important for step counting to work reliably
        developer.log('Starting foreground service...');
        await _flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.startForegroundService(
              _notificationId,
              'Strido is Running',
              message,
              notificationDetails: androidDetails,
            );
        _isForegroundServiceStarted = true;
        developer.log('Foreground service started');
      }
    } catch (e, stackTrace) {
      developer.log(
        'Error updating notification: $e',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  static Future<void> cancel() async {
    await _flutterLocalNotificationsPlugin.cancel(_notificationId);
  }

  /// Check if foreground service is active
  static bool isForegroundServiceActive() {
    return _isForegroundServiceStarted;
  }

  /// Cancel foreground notification
  static Future<void> cancelForegroundNotification() async {
    await cancel();
  }
}
