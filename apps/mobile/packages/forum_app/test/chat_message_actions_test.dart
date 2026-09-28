import 'dart:async';
import 'dart:io';

import 'package:core/core.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:forum_app/src/providers.dart';
import 'package:forum_app/src/widgets/stickers/sticker_image.dart';
import 'package:forum_app/src/widgets/stickers/sticker_library_state.dart';
import 'package:ui_kit/ui_kit.dart';

import 'chat_visible_read_test.dart' show pumpChat, VisibleChatRepository;
import 'pages_behavior_test.dart' show makeChatMessage;

class Tokens implements TokenStorage {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String value) async {}
  @override
  Future<void> clear() async {}
}

GfApiClient _client() => GfApiClient(dio: Dio(), tokenStorage: Tokens());

class Reports extends PostRepository {
  Reports() : super(_client());
  final sent = <Map<String, Object>>[];
  @override
  Future<bool> report({
    required String targetType,
    required int targetId,
    required String reason,
    required String note,
  }) async {
    sent.add({
      'targetType': targetType,
      'targetId': targetId,
      'reason': reason,
      'note': note,
    });
    return true;
  }
}

class RecordingSendsChatRepository extends VisibleChatRepository {
  RecordingSendsChatRepository(super.client, {required super.messages});

  final sent = <(int, String)>[];

  @override
  Future<int> sendMessage({
    required int peerId,
    required String content,
    int msgType = 1,
    String? clientMessageId,
  }) async {
    sent.add((peerId, content));
    return 9;
  }
}

/// 1x1 transparent PNG served to `Image.network` so sticker widgets reach their
/// loaded state instead of the failed-image retry surface.
const List<int> _transparentPng = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
];

class _ImageHttpClient implements HttpClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _ImageHttpRequest();
}

class _ImageHttpRequest implements HttpClientRequest {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  final HttpHeaders headers = _ImageHttpHeaders();

  @override
  Future<HttpClientResponse> close() async => _ImageHttpResponse();
}

class _ImageHttpHeaders implements HttpHeaders {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _ImageHttpResponse implements HttpClientResponse {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  int get statusCode => HttpStatus.ok;

  @override
  int get contentLength => _transparentPng.length;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(_transparentPng).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
}

class _StickerRepository extends StickerRepository {
  _StickerRepository() : super(GfApiClient(dio: Dio(), tokenStorage: Tokens()));

  final saved = <String>[];

  @override
  Future<List<StickerItemPayload>> list() async => const [
    StickerItemPayload(name: 'smile', url: '/smile.png'),
  ];

  @override
  Future<List<StickerItemPayload>> resolve(List<String> names) async =>
      const <StickerItemPayload>[];

  @override
  Future<StickerItemPayload> save({
    String? stickerName,
    String? fileName,
    String? displayName,
  }) async {
    saved.add(stickerName ?? '');
    return StickerItemPayload(name: stickerName ?? '', url: '/smile.png');
  }
}

Future<RecordingSendsChatRepository> pumpActions(
  WidgetTester tester, {
  List<ChatMessagePayload>? messages,
  Reports? reports,
  StickerLibrary? stickers,
  StickerCollection? stickerCollection,
}) async {
  late final RecordingSendsChatRepository repository;
  await pumpChat(
    tester,
    buildRepository: (client) => repository = RecordingSendsChatRepository(
      client,
      messages: messages ?? <ChatMessagePayload>[makeChatMessage(1)],
    ),
    stickers: stickers,
    stickerCollection: stickerCollection,
    overrides: [postRepositoryProvider.overrideWithValue(reports ?? Reports())],
  );
  return repository;
}

Future<void> openActions(WidgetTester tester, Finder bubble) async {
  await tester.longPress(bubble);
  await tester.pumpAndSettle();
}

final Finder _preview = find.byKey(const Key('chat-reply-preview'));

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('long-press on a peer message opens the action menu', (
    tester,
  ) async {
    await pumpActions(tester);
    expect(find.text('Reply'), findsNothing);
    expect(find.text('Copy entire message'), findsNothing);
    await openActions(tester, find.text('消息 1'));
    expect(find.text('Reply'), findsOneWidget);
    expect(find.text('Copy entire message'), findsOneWidget);
    expect(find.text('Report message'), findsOneWidget);
    expect(find.text('Save to my stickers'), findsNothing);
    expect(tester.takeException(), isNull);
    await dispose(tester);
  });

  testWidgets('own messages offer reply and copy without report', (
    tester,
  ) async {
    await pumpActions(
      tester,
      messages: [makeChatMessage(1).copyWith(isSelf: true)],
    );
    await openActions(tester, find.text('消息 1'));
    expect(find.text('Reply'), findsOneWidget);
    expect(find.text('Copy entire message'), findsOneWidget);
    expect(find.text('Report message'), findsNothing);
    await dispose(tester);
  });

  testWidgets('the inline report link is gone and reporting keeps its target', (
    tester,
  ) async {
    final reports = Reports();
    await pumpActions(tester, reports: reports);
    expect(find.widgetWithText(TextButton, 'Report message'), findsNothing);

    await openActions(tester, find.text('消息 1'));
    await tester.tap(find.text('Report message'));
    await tester.pumpAndSettle();
    expect(find.textContaining('rest of the conversation'), findsOneWidget);
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      '这条消息持续骚扰我',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Submit'));
    await tester.pumpAndSettle();
    expect(reports.sent, [
      {
        'targetType': 'chat_message',
        'targetId': 1,
        'reason': 'abuse',
        'note': '这条消息持续骚扰我',
      },
    ]);
    await dispose(tester);
  });

  testWidgets('copying a message writes the whole content to the clipboard', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        calls.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await pumpActions(tester);
    await openActions(tester, find.text('消息 1'));
    await tester.tap(find.text('Copy entire message'));
    await tester.pumpAndSettle();
    final copy = calls.singleWhere(
      (call) => call.method == 'Clipboard.setData',
    );
    expect((copy.arguments as Map<Object?, Object?>)['text'], '消息 1');
    expect(find.text('Copied'), findsOneWidget);
    await dispose(tester);
  });

  testWidgets('choosing reply shows a dismissible quote preview', (
    tester,
  ) async {
    await pumpActions(tester);
    await openActions(tester, find.text('消息 1'));
    await tester.tap(find.text('Reply'));
    await tester.pumpAndSettle();
    expect(_preview, findsOneWidget);
    expect(
      find.descendant(of: _preview, matching: find.text('@bob')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: _preview, matching: find.text('消息 1')),
      findsOneWidget,
    );
    expect(
      tester.getRect(_preview).bottom,
      lessThanOrEqualTo(
        tester.getRect(find.byKey(const Key('chat-input-surface'))).top,
      ),
    );
    await tester.tap(find.byTooltip('Cancel reply'));
    await tester.pumpAndSettle();
    expect(_preview, findsNothing);
    await dispose(tester);
  });

  testWidgets('sending a reply quotes the excerpt and clears the preview', (
    tester,
  ) async {
    final repository = await pumpActions(tester);
    await openActions(tester, find.text('消息 1'));
    await tester.tap(find.text('Reply'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(GfChatInput),
        matching: find.byType(TextField),
      ),
      '收到',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat-send')));
    await tester.pumpAndSettle();
    expect(repository.sent, [(2, '> @bob: 消息 1\n\n收到')]);
    expect(_preview, findsNothing);
    await dispose(tester);
  });

  testWidgets('barrier and system back dismiss the menu without a reply', (
    tester,
  ) async {
    await pumpActions(tester);
    final composer = find.descendant(
      of: find.byType(GfChatInput),
      matching: find.byType(TextField),
    );
    await tester.enterText(composer, '草稿');
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(composer).focusNode!.hasFocus, isTrue);

    await openActions(tester, find.text('消息 1'));
    expect(
      tester.widget<TextField>(composer).focusNode!.hasFocus,
      isFalse,
      reason: 'the menu owns focus while it is open',
    );
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(find.text('Reply'), findsNothing);
    expect(_preview, findsNothing);
    expect(
      FocusManager.instance.primaryFocus?.hasFocus,
      isTrue,
      reason: 'dismissing the menu leaves the page with focus',
    );
    await tester.enterText(composer, '草稿 2');
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(composer).controller!.text, '草稿 2');

    await openActions(tester, find.text('消息 1'));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Reply'), findsNothing);
    expect(_preview, findsNothing);
    expect(tester.widget<TextField>(composer).controller!.text, '草稿 2');
    await dispose(tester);
  });

  testWidgets('menu actions are labelled for screen readers', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpActions(tester);
    await openActions(tester, find.text('消息 1'));
    expect(find.bySemanticsLabel('Reply'), findsOneWidget);
    expect(find.bySemanticsLabel('Report message'), findsOneWidget);
    final node = tester.getSemantics(
      find
          .ancestor(of: find.text('Reply'), matching: find.byType(ListTile))
          .first,
    );
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    handle.dispose();
    await dispose(tester);
  });

  testWidgets('Escape dismisses the action menu', (tester) async {
    await pumpActions(tester);
    await openActions(tester, find.text('消息 1'));
    expect(find.text('Reply'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Reply'), findsNothing);
    expect(_preview, findsNothing);
    await dispose(tester);
  });

  testWidgets('dragging a bubble scrolls instead of opening the menu', (
    tester,
  ) async {
    await pumpActions(
      tester,
      messages: List.generate(30, (index) => makeChatMessage(index + 1)),
    );
    final list = find.byType(ListView).last;
    final scroll = tester.widget<ListView>(list).controller!;
    final before = scroll.offset;
    await tester.drag(find.text('消息 30'), const Offset(0, 160));
    await tester.pumpAndSettle();
    expect(find.text('Reply'), findsNothing);
    expect(scroll.offset, lessThan(before));
    await dispose(tester);
  });

  testWidgets('sticker-only peer messages still open the action menu', (
    tester,
  ) async {
    debugNetworkImageHttpClientProvider = () => _ImageHttpClient();
    final repository = _StickerRepository();
    final library = StickerLibrary(repository);
    addTearDown(library.dispose);
    final collection = StickerCollection(repository, library);
    try {
      await pumpActions(
        tester,
        stickers: library,
        stickerCollection: collection,
        messages: [makeChatMessage(1).copyWith(content: '[:sticker:smile:]')],
      );
      await openActions(tester, find.byType(StickerImage));
      expect(find.text('Reply'), findsOneWidget);
      expect(find.text('Report message'), findsOneWidget);
      expect(find.text('Save to my stickers'), findsOneWidget);
      await tester.tap(find.text('Save to my stickers'));
      await tester.pumpAndSettle();
      expect(repository.saved, ['smile']);
    } finally {
      debugNetworkImageHttpClientProvider = null;
    }
    await dispose(tester);
  });

  testWidgets('the menu and a long quote preview fit a narrow viewport', (
    tester,
  ) async {
    final content = '长内容' * 80;
    await pumpActions(
      tester,
      messages: [makeChatMessage(1).copyWith(content: content)],
    );
    await tester.binding.setSurfaceSize(const Size(320, 600));
    await tester.pumpAndSettle();
    await openActions(tester, find.text(content));
    expect(find.text('Reply'), findsOneWidget);
    await tester.tap(find.text('Reply'));
    await tester.pumpAndSettle();
    expect(_preview, findsOneWidget);
    expect(tester.takeException(), isNull);
    await dispose(tester);
  });
}
