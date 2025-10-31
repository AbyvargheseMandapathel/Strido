
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:strido/presentation/step_counter_page.dart';
import 'package:strido/services/device_sync_service.dart';
import 'package:strido/services/step_tracker_service.dart';

import 'mocks.dart';

void main() {
  late MockStepTrackerService mockStepTrackerService;
  late MockDeviceSyncService mockDeviceSyncService;

  setUp(() {
    mockStepTrackerService = MockStepTrackerService();
    mockDeviceSyncService = MockDeviceSyncService();
  });

  testWidgets('StepCounterPage should save and load step goal', (WidgetTester tester) async {
    // Set up mock shared preferences
    SharedPreferences.setMockInitialValues({});

    // Build our app and trigger a frame.
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<StepTrackerService>.value(value: mockStepTrackerService),
          Provider<DeviceSyncService>.value(value: mockDeviceSyncService),
        ],
        child: MaterialApp(
          home: StepCounterPage(),
        ),
      ),
    );

    // Tap the settings icon to open the dialog.
    await tester.tap(find.byIcon(Icons.flag));
    await tester.pumpAndSettle();

    // Enter a new step goal.
    await tester.enterText(find.byType(TextField), '5000');

    // Tap the save button.
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // Rebuild the widget to simulate a restart.
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<StepTrackerService>.value(value: mockStepTrackerService),
          Provider<DeviceSyncService>.value(value: mockDeviceSyncService),
        ],
        child: MaterialApp(
          home: StepCounterPage(),
        ),
      ),
    );

    // Verify that the new step goal is displayed.
    expect(find.text('Goal: 5000'), findsOneWidget);
  });
}
