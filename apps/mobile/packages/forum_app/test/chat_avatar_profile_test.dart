import 'package:core/core.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsAction, SemanticsNode;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ui_kit/ui_kit.dart';

import 'package:forum_app/l10n/app_localizations.dart';
import 'package:forum_app/src/current_user.dart';
import 'package:forum_app/src/navigation/route_visibility.dart';
import 'package:forum_app/src/pages/messages/messages_page.dart';
import 'package:forum_app/src/pages/profile/profile_page.dart';
import 'package:forum_app/src/providers.dart';

import 'pages_behavior_test.dart'
    show
        CountingPageRepository,
        MemTokenStorage,
        NoopCache,
        PollingChatRepository,
        makeChatMessage;

Finder _appBarAvatar() => find.byKey(const Key('chat-peer-avatar-appbar'));

Finder _rowAvatar(int messageId) =>
    find.byKey(Key('chat-peer-avatar-$messageId'));

/// 打开 /messages?userId=2 目标会话,并注册真实的 /u/:userId 路由。
Future<GoRouter> pumpConversation(
  WidgetTester tester, {
  required List<ChatMessagePayload> messages,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 700));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final storage = MemTokenStorage()..write('token');
  final client = GfApiClient(
    dio: Dio(),
    tokenStorage: storage,
    baseUrl: 'http://fake.local',
  );
  final container = ProviderContainer(
    overrides: [
      tokenStorageProvider.overrideWithValue(storage),
      currentUserProvider.overrideWith(
        (ref) async => const CurrentUser(id: 1, username: 'alice'),
      ),
      pageRepositoryProvider.overrideWithValue(CountingPageRepository(client)),
      chatRepositoryProvider.overrideWithValue(
        PollingChatRepository(client, messages: messages),
      ),
      offlineTopicCacheProvider.overrideWithValue(NoopCache()),
      offlineChatCacheProvider.overrideWithValue(NoopCache()),
    ],
  );
  addTearDown(container.dispose);
  final router = GoRouter(
    initialLocation: '/messages?userId=2&username=Bob',
    observers: <NavigatorObserver>[VisibilityRouteObserver()],
    routes: <RouteBase>[
      GoRoute(
        path: '/messages',
        builder: (_, GoRouterState state) => MessagesPage(
          targetUserId: int.tryParse(state.uri.queryParameters['userId'] ?? ''),
          targetUsername: state.uri.queryParameters['username'] ?? '',
        ),
      ),
      GoRoute(
        path: '/u/:userId',
        builder: (_, GoRouterState state) =>
            ProfilePage(userId: int.parse(state.pathParameters['userId']!)),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        theme: gfThemeData(Brightness.light),
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('顶栏对方头像以 44×44 命中区打开对方主页', (tester) async {
    final router = await pumpConversation(
      tester,
      messages: [makeChatMessage(1)],
    );
    expect(_appBarAvatar(), findsOneWidget);
    expect(tester.getSize(_appBarAvatar()), const Size(44, 44));
    expect(
      tester.getSize(
        find.descendant(of: _appBarAvatar(), matching: find.byType(GfAvatar)),
      ),
      const Size(36, 36),
    );

    await tester.tap(_appBarAvatar());
    await tester.pumpAndSettle();

    expect(router.state.uri.path, '/u/2');
    expect(find.byType(ProfilePage), findsOneWidget);

    router.pop();
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/messages');
    expect(find.text('消息 1'), findsOneWidget);
  });

  testWidgets('消息行对方头像以 44×44 命中区打开对方主页', (tester) async {
    final router = await pumpConversation(
      tester,
      messages: [makeChatMessage(1)],
    );
    final rowAvatar = _rowAvatar(1);
    expect(rowAvatar, findsOneWidget);
    expect(tester.getSize(rowAvatar), const Size(44, 44));
    expect(
      tester.getSize(
        find.descendant(of: rowAvatar, matching: find.byType(GfAvatar)),
      ),
      const Size(32, 32),
    );

    await tester.tap(rowAvatar);
    await tester.pumpAndSettle();

    expect(router.state.uri.path, '/u/2');
    expect(find.byType(ProfilePage), findsOneWidget);
  });

  testWidgets('自己的头像保持展示态,不跳转', (tester) async {
    final router = await pumpConversation(
      tester,
      messages: [makeChatMessage(1), makeChatMessage(2).copyWith(isSelf: true)],
    );
    final selfAvatar = find.byWidgetPredicate(
      (Widget widget) => widget is GfAvatar && widget.size == 32 && widget.ring,
    );
    expect(selfAvatar, findsOneWidget);
    expect(_rowAvatar(2), findsNothing);
    expect(
      find.descendant(of: selfAvatar, matching: find.byType(InkWell)),
      findsNothing,
    );

    await tester.tap(selfAvatar);
    await tester.pumpAndSettle();

    expect(router.state.uri.path, '/messages');
    expect(find.text('消息 2'), findsOneWidget);
  });

  testWidgets('头像入口是带标签的按钮,不劫持消息文本朗读', (tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await pumpConversation(tester, messages: [makeChatMessage(1)]);

    final SemanticsNode avatar = tester.getSemantics(_appBarAvatar());
    expect(avatar.label, '查看 bob 的主页');
    expect(avatar.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);

    final SemanticsNode text = tester.getSemantics(find.text('消息 1'));
    expect(text.label, contains('消息 1'));
    expect(text.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
    handle.dispose();
  });
}
