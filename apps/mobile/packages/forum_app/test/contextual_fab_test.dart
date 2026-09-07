import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_app/l10n/app_localizations.dart';
import 'package:forum_app/src/widgets/contextual_fab.dart';
import 'package:ui_kit/ui_kit.dart';

void main() {
  testWidgets('feed FAB settles before changing and refreshes only on tap', (
    tester,
  ) async {
    final controller = ScrollController();
    int refreshes = 0;
    int publishes = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: gfThemeData(Brightness.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ContextualFab(
            controller: controller,
            onPrimary: () => publishes++,
            onRefresh: () async {
              refreshes++;
            },
            child: ListView(
              controller: controller,
              children: const [SizedBox(height: 3000)],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(FloatingActionButton));
    expect(publishes, 1);
    controller.jumpTo(800);
    await tester.pump(const Duration(milliseconds: 300));
    controller.jumpTo(400);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byIcon(Icons.add_rounded), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
    expect(refreshes, 0);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(refreshes, 1);
    expect(controller.offset, 0);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
  testWidgets(
    'topic top action restores the first window before offering refresh',
    (tester) async {
      final controller = ScrollController();
      var returns = 0;
      var refreshes = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: gfThemeData(Brightness.light),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ContextualFab(
              controller: controller,
              reply: true,
              onPrimary: () {},
              onReturnToTop: () async {
                returns++;
              },
              onRefresh: () async {
                refreshes++;
              },
              child: ListView(
                controller: controller,
                children: const [SizedBox(height: 3000)],
              ),
            ),
          ),
        ),
      );
      controller.jumpTo(800);
      await tester.pump(const Duration(milliseconds: 300));
      controller.jumpTo(400);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byIcon(Icons.vertical_align_top_rounded), findsOneWidget);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(returns, 1);
      expect(refreshes, 0);
      expect(controller.offset, 0);
      expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(refreshes, 1);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
}
