import 'package:flameup/screens/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Finder mainScrollable() => find
      .byWidgetPredicate(
        (Widget widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      )
      .first;

  Future<void> pumpUntilLoaded(WidgetTester tester) async {
    const int maxPumps = 20;
    int pumps = 0;
    while (find.byType(CircularProgressIndicator).evaluate().isNotEmpty &&
        pumps < maxPumps) {
      await tester.pump(const Duration(milliseconds: 100));
      pumps++;
    }
    await tester.pump(const Duration(milliseconds: 200));
  }

  Future<void> pumpHomeScreen(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await pumpUntilLoaded(tester);
  }

  testWidgets(
    'renders the dashboard shell with suggested task and today list',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await pumpHomeScreen(tester);

      expect(find.text('Today'), findsWidgets);
      expect(find.text('Keep today moving'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('suggested-task-card')),
        findsOneWidget,
      );

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey<String>('task-tile-task-2')),
        300,
        scrollable: mainScrollable(),
      );
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Finalize onboarding copy'), findsWidgets);
      expect(find.text('Design sprint review'), findsOneWidget);
    },
  );

  testWidgets('switches to a custom list from the drawer', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await pumpHomeScreen(tester);

    await tester.tap(find.byKey(const ValueKey<String>('open-drawer-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('drawer-list-work')));
    await tester.pumpAndSettle();

    expect(find.text('Work'), findsWidgets);

    await tester.scrollUntilVisible(
      find.text('Plan content calendar'),
      300,
      scrollable: mainScrollable(),
    );
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Plan content calendar'), findsWidgets);
    expect(find.text('Finalize onboarding copy'), findsWidgets);
    expect(find.text('Book dentist appointment'), findsNothing);
  });

  testWidgets('creates a new task and keeps it after rebuild', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await pumpHomeScreen(tester);

    await tester.tap(find.byKey(const ValueKey<String>('quick-add-button')));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    await tester.enterText(
      find.byKey(const ValueKey<String>('add-task-title')),
      'Review launch metrics',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('add-task-note')),
      'Check retention and activation after the release.',
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('save-task-button')),
    );
    await tester.tap(find.byKey(const ValueKey<String>('save-task-button')));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    await tester.scrollUntilVisible(
      find.text('Review launch metrics'),
      300,
      scrollable: mainScrollable(),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Review launch metrics'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    await pumpHomeScreen(tester);
    await tester.scrollUntilVisible(
      find.text('Review launch metrics'),
      300,
      scrollable: mainScrollable(),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Review launch metrics'), findsOneWidget);
  });

  testWidgets('edits a task from the dedicated editor screen', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await pumpHomeScreen(tester);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('task-tile-task-2')),
      300,
      scrollable: mainScrollable(),
    );
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.byKey(const ValueKey<String>('task-tile-task-2')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey<String>('editor-title')),
      'Finalize launch copy',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Finalize launch copy'), findsWidgets);
  });

  testWidgets('updates checkbox state for a task', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await pumpHomeScreen(tester);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('task-tile-task-2')),
      300,
      scrollable: mainScrollable(),
    );
    await tester.pump(const Duration(milliseconds: 200));

    final Finder checkboxFinder = find.byKey(
      const ValueKey<String>('checkbox-Finalize onboarding copy'),
    );
    expect(tester.widget<Checkbox>(checkboxFinder).value, isFalse);

    await tester.tap(checkboxFinder);
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.widget<Checkbox>(checkboxFinder).value, isTrue);
  });

  testWidgets('switches to calendar tab', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await pumpHomeScreen(tester);

    await tester.tap(find.text('Calendar'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('simple-header-title')),
      findsOneWidget,
    );
    expect(find.text('Calendar'), findsWidgets);
  });

  testWidgets('searches tasks from browse tab', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await pumpHomeScreen(tester);

    await tester.tap(find.text('Browse'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey<String>('browse-search-field')),
      'onboarding',
    );
    await tester.pumpAndSettle();

    expect(find.text('Finalize onboarding copy'), findsWidgets);
  });
}
