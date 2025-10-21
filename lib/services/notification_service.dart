import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';
import 'dart:developer' as developer;
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/material.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static const String _channelId = 'strido_channel';
  static const String _channelName = 'Strido Tracker';
  static const String _channelDescription = 'Tracks your steps in the background';
  
  // Check and request notification permissions (required for Android 13+)
  static Future<bool> checkAndRequestPermissions() async {
    try {
      if (!kIsWeb) {
        final plugin = _flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        
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

  static Future<void> init() async {
    try {
      developer.log('Initializing notification service...');
      
      // Check and request notification permissions for Android 13+
      final bool hasPermission = await checkAndRequestPermissions();
      developer.log('Notification permission granted: $hasPermission');

      // Initialize notification channel for Android 8.0+
      developer.log('Creating notification channel...');
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDescription,
        importance: Importance.low,
        playSound: false,
        showBadge: true,
        enableVibration: false,
      );

      await _flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
      developer.log('Notification channel created');

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
      developer.log('Error initializing notifications: $e', 
                   error: e, 
                   stackTrace: stackTrace);
    }
  }

  static Future<void> updateForegroundNotification(int steps, String updatedTime) async {
    try {
      developer.log('Updating foreground notification: $steps steps at $updatedTime');
      
      // Check if notifications are enabled
      final bool? isEnabled = await _flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.areNotificationsEnabled();
      
      if (isEnabled != true) {
        developer.log('Notifications are disabled in system settings');
        return;
      }

      final androidDetails = AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.low,
        priority: Priority.low,
        ongoing: true,
        autoCancel: false,
        icon: 'ic_launcher',
        visibility: NotificationVisibility.public,
        enableLights: true,
        color: const Color(0xFF69F0AE), // Use your app's accent color
        colorized: true,
        showWhen: false,
        onlyAlertOnce: true,
        showProgress: false,
      );

      final iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: false,
      );

      final details = NotificationDetails(android: androidDetails, iOS: iosDetails);
      final String message = '$steps steps as of $updatedTime';

      if (!_isForegroundServiceStarted) {
        developer.log('Starting foreground service...');
        await _flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
            ?.startForegroundService(
              _notificationId,
              'Strido is Running',
              message,
              notificationDetails: androidDetails,
            );
        _isForegroundServiceStarted = true;
        developer.log('Foreground service started');
      } else {
        developer.log('Updating existing notification...');
        await _flutterLocalNotificationsPlugin.show(
          _notificationId,
          'Strido is Running',
          message,
          details,
        );
        developer.log('Notification updated');
      }
    } catch (e, stackTrace) {
      developer.log('Error updating notification: $e', 
                  error: e, 
                  stackTrace: stackTrace);
    }
  }

  static Future<void> cancel() async {
    await _flutterLocalNotificationsPlugin.cancel(_notificationId);
    _isForegroundServiceStarted = false;
  }
}