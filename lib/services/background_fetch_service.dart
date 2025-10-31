import 'package:workmanager/workmanager.dart';
import 'step_tracker_service.dart';
import 'device_sync_service.dart';
import 'notification_service.dart';

const String backgroundTask = "updateStepsTask";

class BackgroundFetchService {
  static Future<void> setup() async {
    await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
    await Workmanager().registerPeriodicTask(
      "strido_step_update",
      backgroundTask,
      frequency: const Duration(minutes: 5),
      initialDelay: const Duration(seconds: 5),
      constraints: Constraints(networkType: NetworkType.not_required),
    );
  }
}

void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task == backgroundTask) {
      // Load steps from phone sensor
      final stepService = StepTrackerService();
      await stepService.initialize();
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final session = await stepService.getSession(today);
      int steps = session?['user_steps'] as int? ?? 0;

      // Merge BLE steps
      final deviceService = DeviceSyncService.instance;
      // deviceService should be auto-connected
      deviceService.loadPaired();
      deviceService.externalStepStream.listen((extSteps) {
        steps += extSteps;
      });

      // Update notification
      await NotificationService.showForegroundNotification(
        title: 'Strido - $steps Steps',
        message: DateTime.now().toIso8601String(),
        isPersistent: true,
      );
    }
    return Future.value(true);
  });
}
