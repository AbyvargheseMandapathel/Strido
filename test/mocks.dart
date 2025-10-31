
import 'package:strido/services/device_sync_service.dart';
import 'package:strido/services/step_tracker_service.dart';
import 'package:mockito/mockito.dart';

class MockStepTrackerService extends Mock implements StepTrackerService {
  @override
  Future<void> initialize() {
    return Future.value();
  }
}

class MockDeviceSyncService extends Mock implements DeviceSyncService {
  @override
  Future<void> loadPaired() {
    return Future.value();
  }
}
