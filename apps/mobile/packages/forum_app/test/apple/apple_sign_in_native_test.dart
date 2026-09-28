import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:forum_app/l10n/app_localizations.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  // Apple's system button is localized by AuthenticationServices from the
  // languages the app bundle declares; Flutter's own localizations do not
  // reach it. See docs/product/mobile-experience.md.
  test('the iOS bundle declares every language the app UI ships', () {
    final plist = read('ios/Runner/Info.plist');
    final block = RegExp(
      r'<key>CFBundleLocalizations</key>\s*<array>([\s\S]*?)</array>',
    ).firstMatch(plist);
    expect(
      block,
      isNotNull,
      reason:
          'Without CFBundleLocalizations the bundle resolves to the '
          'development region and the Apple button stays English.',
    );
    final declared = RegExp(
      r'<string>([^<]+)</string>',
    ).allMatches(block!.group(1)!).map((match) => match.group(1)!).toSet();
    // Simplified Chinese is the only Chinese UI AppLocalizations ships ('zh').
    final uiLanguages = AppLocalizations.supportedLocales
        .map(
          (locale) =>
              locale.languageCode == 'zh' ? 'zh-Hans' : locale.languageCode,
        )
        .toSet();
    expect(declared, uiLanguages);
    expect(declared, contains('zh-Hans'));
  });

  test('the native button applies the Flutter-provided pill radius', () {
    final source = read('ios/Runner/AppleSignIn.swift');
    expect(source, contains(RegExp(r'\["radius"\]')));
    expect(source, contains(RegExp(r'button\.cornerRadius = ')));
    // Only the frame and the corner radius may be adjusted on the official
    // control; the previous fixed 8pt rectangle is gone.
    expect(source, isNot(contains('cornerRadius = 8')));
    // A radius can never exceed half the control height.
    expect(source, contains('frame.height / 2'));
  });
}
