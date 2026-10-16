import 'package:flutter_test/flutter_test.dart';
import 'package:forum_app/src/link_navigation.dart';

void main() {
  tearDown(() {
    LinkNavigation.clearSessionTrust();
    LinkNavigation.applyTrustedDomains(const <String>[]);
  });

  test('session trust uses the Public Suffix List registrable domain', () {
    expect(
      LinkNavigation.trustDomainFor('docs.team.example.co.uk'),
      'example.co.uk',
    );

    LinkNavigation.trustForSession('docs.team.example.co.uk');
    expect(LinkNavigation.isTrusted('status.example.co.uk'), isTrue);
    expect(LinkNavigation.isTrusted('example.com'), isFalse);
  });

  test('private suffix tenants do not share trust', () {
    LinkNavigation.trustForSession('alice.github.io');
    expect(LinkNavigation.isTrusted('alice.github.io'), isTrue);
    expect(LinkNavigation.isTrusted('bob.github.io'), isFalse);
  });

  test('policy whitelist entries match the host and its subdomains only', () {
    // 大小写/空白/根点归一化；单标签条目（localhost）被丢弃（issue #1200）。
    LinkNavigation.applyTrustedDomains(<String>[
      '  GitHub.com. ',
      'localhost',
      'github.com',
    ]);
    expect(LinkNavigation.isPolicyTrusted('github.com'), isTrue);
    expect(LinkNavigation.isPolicyTrusted('gist.github.com'), isTrue);
    // 点边界比较：伪装后缀与同级域名都不继承白名单。
    expect(LinkNavigation.isPolicyTrusted('github.com.evil.test'), isFalse);
    expect(LinkNavigation.isPolicyTrusted('notgithub.com'), isFalse);
    expect(LinkNavigation.isPolicyTrusted('localhost'), isFalse);
  });

  test('mislabeledLinkTargets flags URL labels pointing elsewhere', () {
    // 与 Web 的 linkRisk 等价：标签是站外 URL 且 registrable domain 与目标不同。
    expect(
      mislabeledLinkTargets(
        '[https://bank.example/account](https://github.com/x)',
      ),
      <String>{'https://github.com/x'},
    );
    // 同注册域的标签（含子域）不是误导性标签。
    expect(
      mislabeledLinkTargets(
        '[https://docs.example.com](https://example.com/y)',
      ),
      isEmpty,
    );
    // 普通文字标签、相对目标、自动链接都不成卡。
    expect(
      mislabeledLinkTargets(
        '[文档](https://github.com/x) [https://bank.example](/relative) <https://github.com/z>',
      ),
      isEmpty,
    );
  });

  test('IDN policy entries match the percent-encoded host Dart parses', () {
    // 服务端把 IDN 条目存成 punycode（idna.Lookup.ToASCII），而 Dart 的
    // Uri.host 给的是百分号编码形式（issue #1200 review）。
    LinkNavigation.applyTrustedDomains(<String>['xn--fiqs8s.com']); // 中国.com
    expect(
      LinkNavigation.isPolicyTrusted(Uri.parse('https://中国.com/x').host),
      isTrue,
    );
    expect(LinkNavigation.isPolicyTrusted('xn--fiqs8s.com'), isTrue);
    expect(LinkNavigation.isPolicyTrusted('www.xn--fiqs8s.com'), isTrue);
    expect(LinkNavigation.isPolicyTrusted('xn--fiqs8s.com.evil.test'), isFalse);
  });

  test(
    'normalizeTrustedDomains lowercases, dedupes and drops unusable entries',
    () {
      expect(
        normalizeTrustedDomains(<String>[
          'GitHub.com',
          'github.com',
          '',
          '   ',
          'localhost',
          '中国.com',
        ]),
        <String>{'github.com', 'xn--fiqs8s.com'},
      );
    },
  );
}
