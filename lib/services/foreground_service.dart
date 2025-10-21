import 'notification_service.dart';

class ForegroundService {
  static Future<void> start() async {
    // Just initialize notification
    await NotificationService.init();
    // Can optionally show 0 steps initially
    await NotificationService.updateForegroundNotification(0, DateTime.now().toIso8601String());
  }
}
