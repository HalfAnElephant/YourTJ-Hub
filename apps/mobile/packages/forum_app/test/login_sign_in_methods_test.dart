import 'dart:convert';

import 'package:auth/auth.dart';
import 'package:core/core.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_app/l10n/app_localizations.dart';
import 'package:forum_app/src/apple/apple_sign_in_button.dart';
import 'package:forum_app/src/pages/auth/login_page.dart';
import 'package:forum_app/src/pages/auth/sign_in_methods_sheet.dart';
import 'package:forum_app/src/providers.dart';
import 'package:ui_kit/ui_kit.dart';

import 'fixtures/page_fixtures.dart';
import 'pages_behavior_test.dart' show NoopCache;
import 'pages_smoke_test.dart' show MemoryTokenStorage;

const Key moreMethodsKey = Key('login-more-methods');

/// Serves the `/login` page payload with a configurable provider set.
class _LoginOptions implements HttpClientAdapter {
  _LoginOptions({
    required this.tongji,
    required this.google,
    required this.github,
    required this.apple,
    required this.policies,
  });

  final bool tongji;
  final bool google;
  final bool github;
  final bool apple;
  final bool policies;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions request,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (request.path != '/login') {
      throw DioException(
        requestOptions: request,
        type: DioExceptionType.connectionError,
      );
    }
    return ResponseBody.fromString(
      jsonEncode({
        'component': 'auth.login',
        'props': {
          'initialMode': 'login',
          'redirectUrl': '/',
          'githubUrl': github ? '/api/auth/github' : '',
          'googleReady': google,
          'appleReady': apple,
          'tongjiReady': tongji,
          'tongjiUrl': tongji ? '/api/auth/tongji' : '',
          'allowedDomains': <String>[],
          'termsOfServiceEnabled': policies,
          'privacyPolicyEnabled': policies,
        },
        'layout': minimalLayoutJson(),
        'url': '/login',
        'version': '1',
        'meta': {'title': 'Login'},
      }),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }
}

class _Harness {
  _Harness(this.tester, this.container, this.l10n);

  final WidgetTester tester;
  final ProviderContainer container;
  final AppLocalizations l10n;

  Finder get control => find.byKey(moreMethodsKey);

  ScrollPosition get scroll => tester
      .state<ScrollableState>(
        find
            .descendant(
              of: find.byType(SingleChildScrollView).first,
              matching: find.byType(Scrollable),
            )
            .first,
      )
      .position;

  double get scrollExtent => scroll.maxScrollExtent;

  double get contentHeight => scroll.maxScrollExtent + scroll.viewportDimension;

  Future<void> openControl() async {
    await tester.ensureVisible(control);
    await tester.pumpAndSettle();
    await tester.tap(control);
    await tester.pumpAndSettle();
  }
}

Future<_Harness> _pumpLogin(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  bool tongji = true,
  bool google = true,
  bool github = true,
  bool apple = false,
  bool policies = true,
  Locale locale = const Locale('en'),
  double textScale = 1,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final storage = MemoryTokenStorage();
  final client = GfApiClient(
    dio: Dio(),
    tokenStorage: storage,
    baseUrl: 'http://fake.local',
  );
  final adapter = _LoginOptions(
    tongji: tongji,
    google: google,
    github: github,
    apple: apple,
    policies: policies,
  );
  final container = ProviderContainer(
    overrides: [
      dioProvider.overrideWithValue(Dio()..httpClientAdapter = adapter),
      authDioProvider.overrideWithValue(Dio()..httpClientAdapter = adapter),
      tokenStorageProvider.overrideWithValue(storage),
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
        locale: locale,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: LoginPage(
          // A fresh page per pump: the state owns the loaded login options.
          key: UniqueKey(),
          authController: AuthController(
            authRepository: AuthRepository(client),
            apiClient: client,
            tokenStorage: MemoryTokenStorage(),
          ),
          authTokenStorage: MemoryTokenStorage(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _Harness(
    tester,
    container,
    AppLocalizations.of(tester.element(find.byType(LoginPage))),
  );
}

void main() {
  for (final language in ['zh', 'en', 'ja', 'de']) {
    testWidgets('a common phone fits the $language sign-in page without '
        'scrolling', (tester) async {
      final h = await _pumpLogin(tester, locale: Locale(language));
      expect(tester.takeException(), isNull);
      expect(h.scrollExtent, 0);
      expect(h.control, findsOneWidget);
      expect(h.control.hitTestable(), findsOneWidget);
      expect(tester.getSize(h.control).height, greaterThanOrEqualTo(44));
      // The account form stays the visible primary entry.
      expect(find.text(h.l10n.authPassword), findsOneWidget);
      expect(find.text(h.l10n.authLoginTitle), findsWidgets);
    });
  }

  testWidgets('the collapsed control adds one row on a short phone', (
    tester,
  ) async {
    final withProviders = await _pumpLogin(tester, size: const Size(360, 640));
    final double contentWithProviders = withProviders.contentHeight;
    expect(tester.takeException(), isNull);

    final withoutProviders = await _pumpLogin(
      tester,
      size: const Size(360, 640),
      tongji: false,
      google: false,
      github: false,
    );
    expect(tester.takeException(), isNull);
    expect(withoutProviders.control, findsNothing);

    // Two provider buttons, the section label and the Tongji notice used to
    // push this page far past the viewport; the collapsed control costs one
    // row plus its gap.
    expect(
      contentWithProviders - withoutProviders.contentHeight,
      lessThanOrEqualTo(68),
    );
  });

  testWidgets('the control opens one sheet with every available provider', (
    tester,
  ) async {
    final h = await _pumpLogin(tester, apple: true);
    expect(
      tester.widget<OutlinedButton>(h.control).focusNode?.hasFocus,
      isFalse,
    );

    await tester.tap(h.control);
    await tester.pumpAndSettle();

    expect(find.byType(SignInMethodsSheet), findsOneWidget);
    expect(find.text(h.l10n.authSignInMethods), findsWidgets);
    expect(find.text(h.l10n.loginTongji), findsOneWidget);
    expect(find.text(h.l10n.loginGoogle), findsOneWidget);
    expect(find.text(h.l10n.loginGithub), findsOneWidget);
    expect(find.text(h.l10n.loginTongjiHint), findsOneWidget);
    expect(find.text(h.l10n.loginTongjiPolicies), findsOneWidget);
    // Apple stays gated to native iOS sign-in.
    expect(
      find.byType(AppleSignInButton),
      defaultTargetPlatform == TargetPlatform.iOS
          ? findsOneWidget
          : findsNothing,
    );
    for (final label in [
      h.l10n.loginTongji,
      h.l10n.loginGoogle,
      h.l10n.loginGithub,
    ]) {
      final target = find.ancestor(
        of: find.text(label),
        matching: find.byType(OutlinedButton),
      );
      expect(target, findsOneWidget);
      final size = tester.getSize(target);
      expect(size.height, greaterThanOrEqualTo(44));
      expect(size.width, greaterThanOrEqualTo(44));
    }
    // Focus leaves the page control and enters the sheet.
    expect(
      tester.widget<OutlinedButton>(h.control).focusNode?.hasFocus,
      isFalse,
    );
    final sheetContext = tester.element(find.byType(SignInMethodsSheet));
    expect(FocusScope.of(sheetContext).hasFocus, isTrue);
  });

  testWidgets('dismissing the sheet restores the form and the control focus', (
    tester,
  ) async {
    final h = await _pumpLogin(tester);
    await h.openControl();
    expect(find.byType(SignInMethodsSheet), findsOneWidget);

    await tester.tapAt(const Offset(195, 40));
    await tester.pumpAndSettle();

    expect(find.byType(SignInMethodsSheet), findsNothing);
    expect(find.text(h.l10n.loginGoogle), findsNothing);
    expect(find.text(h.l10n.authPassword), findsOneWidget);
    expect(h.control, findsOneWidget);
    expect(
      tester.widget<OutlinedButton>(h.control).focusNode?.hasFocus,
      isTrue,
    );
  });

  testWidgets('Escape dismisses the sheet', (tester) async {
    final h = await _pumpLogin(tester);
    await h.openControl();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(SignInMethodsSheet), findsNothing);
  });

  testWidgets('an unconfigured provider never appears', (tester) async {
    final none = await _pumpLogin(
      tester,
      tongji: false,
      google: false,
      github: false,
    );
    expect(none.control, findsNothing);

    final googleOnly = await _pumpLogin(
      tester,
      tongji: false,
      google: true,
      github: false,
    );
    expect(googleOnly.control, findsOneWidget);
    await googleOnly.openControl();
    expect(find.text(googleOnly.l10n.loginGoogle), findsOneWidget);
    expect(find.text(googleOnly.l10n.loginTongji), findsNothing);
    expect(find.text(googleOnly.l10n.loginGithub), findsNothing);
    expect(find.text(googleOnly.l10n.loginTongjiHint), findsNothing);
  });

  testWidgets('a small phone with large text still reaches every provider', (
    tester,
  ) async {
    final h = await _pumpLogin(
      tester,
      size: const Size(320, 568),
      textScale: 2,
    );
    await h.openControl();
    expect(find.byType(SignInMethodsSheet), findsOneWidget);
    expect(find.text(h.l10n.loginTongji), findsOneWidget);
    expect(find.text(h.l10n.loginGoogle), findsOneWidget);
    expect(find.text(h.l10n.loginGithub), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the folded control and its sheet are announced', (tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    final h = await _pumpLogin(tester);

    final SemanticsNode control = tester.semantics.find(h.control);
    expect(control.flagsCollection.isButton, isTrue);
    expect(control.label, contains(h.l10n.authMoreSignInMethods));

    await h.openControl();
    expect(
      tester.semantics.find(find.text(h.l10n.authSignInMethods)).label,
      contains(h.l10n.authSignInMethods),
    );
    expect(find.bySemanticsLabel(h.l10n.loginTongji), findsOneWidget);
    expect(find.bySemanticsLabel(h.l10n.loginGoogle), findsOneWidget);
    handle.dispose();
  });

  testWidgets('choosing a provider closes the sheet with that method', (
    tester,
  ) async {
    SignInMethod? selected;
    await tester.pumpWidget(
      MaterialApp(
        theme: gfThemeData(Brightness.light),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  selected = await showGfBottomSheet<SignInMethod>(
                    context,
                    builder: (_) => const SignInMethodsSheet(
                      methods: [
                        SignInMethod.tongji,
                        SignInMethod.google,
                        SignInMethod.github,
                      ],
                      termsOfServiceEnabled: false,
                      privacyPolicyEnabled: false,
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    expect(selected, SignInMethod.google);
    expect(find.byType(SignInMethodsSheet), findsNothing);
  });

  group('availableSignInMethods', () {
    LoginPageProps options({
      bool tongji = false,
      bool google = false,
      bool github = false,
      bool apple = false,
    }) => LoginPageProps(
      initialMode: 'login',
      redirectUrl: '/',
      githubUrl: github ? '/api/auth/github' : '',
      googleReady: google,
      appleReady: apple,
      tongjiReady: tongji,
    );

    test('login lists every published provider in display order', () {
      expect(
        availableSignInMethods(
          options(tongji: true, google: true, github: true, apple: true),
          loginMode: true,
          nativeAppleAvailable: true,
        ),
        [
          SignInMethod.apple,
          SignInMethod.tongji,
          SignInMethod.google,
          SignInMethod.github,
        ],
      );
    });

    test('Apple needs a configured site and native iOS sign-in', () {
      expect(
        availableSignInMethods(
          options(apple: true),
          loginMode: true,
          nativeAppleAvailable: false,
        ),
        isEmpty,
      );
      expect(
        availableSignInMethods(
          options(apple: true),
          loginMode: true,
          nativeAppleAvailable: true,
        ),
        [SignInMethod.apple],
      );
    });

    test('registration keeps only Tongji', () {
      expect(
        availableSignInMethods(
          options(tongji: true, google: true, github: true, apple: true),
          loginMode: false,
          nativeAppleAvailable: true,
        ),
        [SignInMethod.tongji],
      );
    });
  });
}
