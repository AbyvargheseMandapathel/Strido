import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker_app/presentation/step_counter_page.dart';
import 'package:flutter/material.dart';

void main() {
  testWidgets('StepCounterPage displays step count and goal completion', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: StepCounterPage()));

    // Verify initial step count and goal
    expect(find.text('0'), findsOneWidget);
    expect(find.text('Goal: 10000'), findsOneWidget);
    expect(find.text('0%'), findsOneWidget);

    // Simulate updating steps
    await tester.pumpAndSettle();
    // Assuming there's a method to update steps, we would call it here
    // For example: stepCounterPage.updateSteps(5000);
    // await tester.pumpAndSettle();

    // Verify updated step count and goal completion
    // expect(find.text('5000'), findsOneWidget);
    // expect(find.text('Goal: 10000'), findsOneWidget);
    // expect(find.text('50%'), findsOneWidget);
  });

  testWidgets('StepCounterPage shows last updated time', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: StepCounterPage()));

    // Verify initial last updated message
    expect(find.text('Last updated: never'), findsOneWidget);

    // Simulate a last updated time
    // Assuming there's a method to update last updated time, we would call it here
    // For example: stepCounterPage.updateLastUpdated(DateTime.now().toIso8601String());
    // await tester.pumpAndSettle();

    // Verify updated last updated message
    // expect(find.textContaining('Last updated: '), findsOneWidget);
  });
}