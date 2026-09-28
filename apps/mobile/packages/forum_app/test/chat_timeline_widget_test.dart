import 'package:core/core.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ui_kit/ui_kit.dart';

import 'package:forum_app/l10n/app_localizations.dart';
import 'package:forum_app/src/current_user.dart';
import 'package:forum_app/src/pages/messages/messages_page.dart';
import 'package:forum_app/src/providers.dart';

import 'chat_visible_read_test.dart' show VisibleChatRepository;
import 'pages_behavior_test.dart'
    show CountingPageRepository, MemTokenStorage, NoopCache;

/// 撑高气泡的正文：小屏下列表可滚动，上翻分页路径才会被触发，
/// 且首屏消息仍在懒加载视口内。
String _body(int id) => '消息 $id${'\n正文' * 3}';

ChatMessagePayload _message(
  int id,
  DateTime at, {
  bool isSelf = false,
  String? content,
}) {
  return ChatMessagePayload(
    id: id,
    senderId: isSelf ? 1 : 2,
    content: content ?? '消息 $id',
    msgType: 1,
    isRead: 1,
    // 设备本地墙钟对应的绝对时刻，与设备时区无关。
    createdAt: at.toUtc().toIso8601String(),
    isSelf: isSelf,
  );
}

Finder _dateSeparators() => find.byWidgetPredicate(
  (Widget widget) =>
      widget.key is ValueKey<String> &&
      (widget.key! as ValueKey<String>).value.startsWith(
        'chat-date-separator-',
      ),
);

Future<VisibleChatRepository> _pumpConversation(
  WidgetTester tester,
  List<ChatMessagePayload> messages, {
  List<ChatMessagePayload>? older,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 700));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final storage = MemTokenStorage()..write('token');
  final client = GfApiClient(
    dio: Dio(),
    tokenStorage: storage,
    baseUrl: 'http://fake.local',
  );
  final repo = VisibleChatRepository(
    client,
    hasMoreBefore: older != null,
    messages: messages,
  )..olderMessages = older ?? <ChatMessagePayload>[];
  final container = ProviderContainer(
    overrides: [
      tokenStorageProvider.overrideWithValue(storage),
      currentUserProvider.overrideWith(
        (ref) async => const CurrentUser(id: 1, username: 'alice'),
      ),
      pageRepositoryProvider.overrideWithValue(CountingPageRepository(client)),
      chatRepositoryProvider.overrideWithValue(repo),
      offlineTopicCacheProvider.overrideWithValue(NoopCache()),
      offlineChatCacheProvider.overrideWithValue(NoopCache()),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: gfThemeData(Brightness.light),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const MessagesPage(targetUserId: 2),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

List<String?> _bubbleTimes(WidgetTester tester) => tester
    .widgetList<GfMessageBubble>(find.byType(GfMessageBubble))
    .map((GfMessageBubble bubble) => bubble.time)
    .toList();

/// 读取指定消息气泡上的时刻；气泡未构建时断言失败（测试需保证其在视口内）。
String? _bubbleTimeFor(WidgetTester tester, int id) {
  final Finder finder = find.ancestor(
    of: find.text(_body(id)),
    matching: find.byType(GfMessageBubble),
  );
  expect(finder, findsOneWidget);
  return tester.widget<GfMessageBubble>(finder).time;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('每个日历日只显示一个日期分隔，冗余的气泡时间被隐藏', (tester) async {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day, 10, 0);
    final DateTime yesterday = DateTime(
      now.year,
      now.month,
      now.day - 1,
      23,
      50,
    );
    await _pumpConversation(tester, <ChatMessagePayload>[
      _message(1, yesterday),
      _message(2, yesterday.add(const Duration(minutes: 2))),
      _message(3, today),
      _message(4, today.add(const Duration(minutes: 2))),
      _message(5, today.add(const Duration(minutes: 10)), isSelf: true),
    ]);

    expect(_dateSeparators(), findsNWidgets(2));
    expect(find.text('Yesterday'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(_bubbleTimes(tester), <String?>[
      '23:50',
      null,
      '10:00',
      null,
      '10:10',
    ]);
  });

  testWidgets('日期分隔以标题语义暴露，不读作消息内容', (tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day, 9, 0);
    await _pumpConversation(tester, <ChatMessagePayload>[
      _message(1, today),
      _message(2, today.add(const Duration(hours: 2))),
    ]);

    expect(_dateSeparators(), findsOneWidget);
    final SemanticsNode node = tester.getSemantics(find.text('Today'));
    expect(node.flagsCollection.isHeader, isTrue);
    expect(node.label, 'Today');
    // 消息气泡不携带标题语义,读屏不会把日期分隔混进消息流。
    expect(
      tester.getSemantics(find.text('消息 1')).flagsCollection.isHeader,
      isFalse,
    );
    handle.dispose();
  });

  testWidgets('上翻加载更早一页后不重复日期分隔，边界气泡改为不显示时间', (tester) async {
    final DateTime now = DateTime.now();
    final DateTime day = DateTime(now.year, now.month, now.day, 9, 57);
    final VisibleChatRepository repo = await _pumpConversation(
      tester,
      <ChatMessagePayload>[
        _message(101, day.add(const Duration(minutes: 3)), content: _body(101)),
        _message(102, day.add(const Duration(minutes: 6)), content: _body(102)),
        _message(103, day.add(const Duration(minutes: 9)), content: _body(103)),
      ],
      older: <ChatMessagePayload>[
        _message(99, day, content: _body(99)),
        _message(100, day.add(const Duration(minutes: 1)), content: _body(100)),
      ],
    );

    final ScrollController controller = tester
        .widget<ListView>(find.byType(ListView).last)
        .controller!;
    controller.jumpTo(0);
    await tester.pumpAndSettle();
    expect(repo.beforeCalls, greaterThan(0));

    // 分页锚点会把视口留在原处；再回到顶部检查更早一页的渲染。
    controller.jumpTo(0);
    await tester.pumpAndSettle();

    // 更早一页成为列表首条：日期分隔随之移动，不重复。
    expect(
      find.byKey(const ValueKey<String>('chat-date-separator-99')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('chat-date-separator-101')),
      findsNothing,
    );
    // 101 与前置消息只差 2 分钟，不再是分组首条。
    expect(_bubbleTimeFor(tester, 99), '09:57');
    expect(_bubbleTimeFor(tester, 100), isNull);
    expect(_bubbleTimeFor(tester, 101), isNull);
  });

  testWidgets('没有消息时不显示日期分隔', (tester) async {
    await _pumpConversation(tester, const <ChatMessagePayload>[]);

    expect(_dateSeparators(), findsNothing);
    expect(find.byType(GfMessageBubble), findsNothing);
  });
}
