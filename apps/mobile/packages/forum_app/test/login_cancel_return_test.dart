import 'dart:convert';
import 'dart:typed_data';

import 'package:auth/auth.dart';
import 'package:core/core.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ui_kit/ui_kit.dart';

import 'package:forum_app/l10n/app_localizations.dart';
import 'package:forum_app/src/app.dart';
import 'package:forum_app/src/offline/drift_cache.dart';
import 'package:forum_app/src/pages/auth/login_page.dart';
import 'package:forum_app/src/providers.dart';
import 'package:forum_app/src/router.dart';

import 'fixtures/page_fixtures.dart';

/// 测试用内存 TokenStorage(空 = 未登录)。
class _MemoryTokenStorage implements TokenStorage {
  String? _token;

  @override
  Future<String?> read() async => _token;

  @override
  Future<void> write(String token) async => _token = token;

  @override
  Future<void> clear() async => _token = null;
}

/// 测试用 no-op 离线缓存(避免 widget 测试打开真实 sqlite 库)。
class _NoopOfflineCache implements OfflineTopicCache, OfflineChatCache {
  @override
  Future<void> put(int topicId, Map<String, dynamic> payload) async {}

  @override
  Future<PagePayload?> get(int topicId) async => null;

  @override
  Future<void> putConversations(List<ChatItemPayload> conversations) async {}

  @override
  Future<List<ChatItemPayload>> getConversations() async => const [];

  @override
  Future<void> putMessages(
    int convId,
    List<ChatMessagePayload> messages,
  ) async {}

  @override
  Future<List<ChatMessagePayload>> getMessages(int convId) async => const [];

  @override
  Future<void> clear() async {}

  @override
  Future<void> close() async {}
}

Map<String, dynamic> _loginPayloadJson() => <String, dynamic>{
  'component': 'auth.login',
  'props': <String, dynamic>{
    'initialMode': 'login',
    'redirectUrl': '/',
    'githubUrl': '/api/auth/github',
    'googleReady': false,
    'tongjiReady': false,
    'tongjiUrl': '/api/auth/tongji',
    'allowedDomains': <String>[],
    'termsOfServiceEnabled': false,
    'privacyPolicyEnabled': false,
  },
  'layout': minimalLayoutJson(),
  'url': '/login',
  'version': '1.0',
  'meta': <String, dynamic>{'title': 'Login'},
};

/// 游客可读话题(canPost=false),评论入口因此跳转登录页。
class _GuestPageRepository extends PageRepository {
  _GuestPageRepository(super.client);

  @override
  Future<PagePayload> fetch(String path, {CancelToken? cancelToken}) async {
    if (path == '/' || path.startsWith('/?sort=')) {
      return parsePayload(homePayloadJson());
    }
    if (path.startsWith('/p/post/')) {
      final payload = topicDetailPayloadJson();
      payload['props'] = <String, dynamic>{
        ...payload['props'] as Map<String, dynamic>,
        'permissions': <String, dynamic>{
          'isOwnTopic': false,
          'canPost': false,
          'canModerateTopic': false,
        },
      };
      return parsePayload(payload);
    }
    if (path == '/login') {
      return parsePayload(_loginPayloadJson());
    }
    throw UnimplementedError('unexpected page path: $path');
  }
}

/// 只服务登录页 props 的适配器(避免真实网络)。
class _LoginPropsAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions request,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    expect(request.path, '/login');
    return ResponseBody.fromString(
      jsonEncode(_loginPayloadJson()),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }
}

/// 提交即成功的内存控制器:令牌写入暂存区并进入 authenticated 阶段,
/// 由真实的 `_finishAuthentication` 完成清库、提交与返回目标页。
class _AuthenticatingAuth extends AuthController {
  _AuthenticatingAuth(GfApiClient client, TokenStorage staged)
    : _staged = staged,
      super(
        authRepository: AuthRepository(client),
        apiClient: client,
        tokenStorage: staged,
      );

  final TokenStorage _staged;
  bool _authenticated = false;

  @override
  LoginPhase get phase =>
      _authenticated ? LoginPhase.authenticated : super.phase;

  @override
  Future<void> loadCaptcha({
    bool preservePhaseOnError = false,
    bool silentOnError = false,
  }) async {}

  @override
  Future<void> login({
    required String username,
    required String password,
    String? captchaId,
    String? captchaCode,
  }) async {
    await _staged.write('new-session-token');
    _authenticated = true;
    notifyListeners();
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('cancelling login returns to the topic that opened it', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    final storage = _MemoryTokenStorage();
    final client = GfApiClient(
      dio: Dio(),
      tokenStorage: storage,
      baseUrl: 'http://fake.local',
    );
    final container = ProviderContainer(
      overrides: [
        tokenStorageProvider.overrideWithValue(storage),
        pageRepositoryProvider.overrideWithValue(_GuestPageRepository(client)),
        offlineTopicCacheProvider.overrideWithValue(_NoopOfflineCache()),
        offlineChatCacheProvider.overrideWithValue(_NoopOfflineCache()),
      ],
    );
    addTearDown(container.dispose);

    appRouter.go('/');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const GfApp(locale: Locale('zh')),
      ),
    );
    await tester.pumpAndSettle();

    appRouter.push('/p/100');
    await tester.pumpAndSettle();
    expect(find.text('移动端测试话题'), findsWidgets);
    expect(find.text('第一楼'), findsOneWidget);

    // 游客点“参与讨论”:进入登录页。
    await tester.tap(find.text('参与讨论'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
    expect(appRouter.state.uri.path, '/login');

    // 取消登录:应回到原帖,而不是空脚手架/黑屏。
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();

    expect(find.byType(LoginPage), findsNothing);
    expect(appRouter.state.uri.path, '/p/100');
    expect(find.text('第一楼'), findsOneWidget);

    // 反复打开/取消必须稳定:第二次进入登录页时原帖仍在下方。
    await tester.tap(find.text('参与讨论'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsNothing);
    expect(appRouter.state.uri.path, '/p/100');
    expect(find.text('第一楼'), findsOneWidget);

    // markdown_widget 的 VisibilityDetector 会创建 500ms 延迟 Timer,
    // 需推进时钟让其过期,避免 "Timer is still pending"。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 600));
  });

  Future<ProviderContainer> pumpLoginPage(
    WidgetTester tester, {
    required bool existingSession,
  }) async {
    final storage = _MemoryTokenStorage();
    if (existingSession) await storage.write('old-session');
    final adapter = _LoginPropsAdapter();
    final container = ProviderContainer(
      overrides: [
        dioProvider.overrideWithValue(Dio()..httpClientAdapter = adapter),
        authDioProvider.overrideWithValue(Dio()..httpClientAdapter = adapter),
        tokenStorageProvider.overrideWithValue(storage),
        offlineTopicCacheProvider.overrideWithValue(_NoopOfflineCache()),
        offlineChatCacheProvider.overrideWithValue(_NoopOfflineCache()),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const LoginPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('guest login entry keeps the current session boundary', (
    tester,
  ) async {
    final container = await pumpLoginPage(tester, existingSession: false);

    // 游客打开登录页不是账号切换:下方仍存活的页面必须继续可用。
    expect(container.read(offlineCacheEpochProvider), 0);
  });

  testWidgets('login entry with an existing session advances the boundary', (
    tester,
  ) async {
    final container = await pumpLoginPage(tester, existingSession: true);

    expect(container.read(offlineCacheEpochProvider), 1);
  });

  Finder input(String label) => find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label,
  );
  Finder submit() => find.byWidgetPredicate(
    (widget) => widget is GfButton && widget.size == GfButtonSize.extraLarge,
  );

  testWidgets(
    'successful login advances the boundary and restores the target',
    (tester) async {
      final storage = _MemoryTokenStorage();
      final staged = _MemoryTokenStorage();
      final adapter = _LoginPropsAdapter();
      final container = ProviderContainer(
        overrides: [
          dioProvider.overrideWithValue(Dio()..httpClientAdapter = adapter),
          authDioProvider.overrideWithValue(Dio()..httpClientAdapter = adapter),
          tokenStorageProvider.overrideWithValue(storage),
          offlineTopicCacheProvider.overrideWithValue(_NoopOfflineCache()),
          offlineChatCacheProvider.overrideWithValue(_NoopOfflineCache()),
        ],
      );
      addTearDown(container.dispose);
      final authClient = GfApiClient(
        dio: Dio(),
        tokenStorage: staged,
        baseUrl: 'http://fake.local',
      );
      final auth = _AuthenticatingAuth(authClient, staged);
      final router = GoRouter(
        initialLocation: '/login?returnTo=%2Fp%2F100',
        routes: <RouteBase>[
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(body: Text('home')),
          ),
          GoRoute(
            path: '/p/:postId',
            builder: (_, state) =>
                Scaffold(body: Text('topic-${state.pathParameters['postId']}')),
          ),
          GoRoute(
            path: '/login',
            builder: (_, _) =>
                LoginPage(authController: auth, authTokenStorage: staged),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: router,
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsOneWidget);

      await tester.enterText(input('Username or email'), 'mobile');
      await tester.enterText(input('Password'), 'test-password');
      await tester.pumpAndSettle();
      await tester.tap(submit());
      await tester.pumpAndSettle();

      // 认证成功是账号切换:推进入口未推进的会话世代并提交令牌。
      expect(container.read(offlineCacheEpochProvider), 1);
      expect(await storage.read(), 'new-session-token');
      // 登录后继续到发起登录前的目标页面。
      expect(router.state.uri.path, '/p/100');
      expect(find.text('topic-100'), findsOneWidget);
    },
  );
}
