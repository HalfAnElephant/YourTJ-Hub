import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ui_kit/ui_kit.dart';

import 'chat_visible_read_test.dart' show pumpChat;
import 'pages_behavior_test.dart' show makeChatMessage;

/// Asserts the circular-avatar contract on every DM surface.
///
/// Regression guard for issue #877 (DM avatars reported as hexagons): the
/// conversation list and both message directions must keep a circular
/// decoration clipped with [Clip.antiAlias] at the documented size.
void expectCircularAvatar(
  WidgetTester tester,
  Finder avatarFinder, {
  required double size,
  required bool ring,
}) {
  final GfAvatar avatar = tester.widget<GfAvatar>(avatarFinder);
  expect(avatar.size, size);
  expect(avatar.ring, ring);

  final Container container = tester.widget<Container>(
    find.descendant(of: avatarFinder, matching: find.byType(Container)).first,
  );
  final BoxDecoration decoration = container.decoration! as BoxDecoration;
  expect(
    decoration.shape,
    BoxShape.circle,
    reason: 'DM avatars must stay circular (issue #877)',
  );
  expect(
    container.clipBehavior,
    Clip.antiAlias,
    reason: 'the image must be clipped to the circular decoration',
  );
  expect(decoration.border, ring ? isNotNull : isNull);
  expect(tester.getSize(avatarFinder), Size(size, size));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('conversation list rows keep circular 40px avatars', (
    tester,
  ) async {
    await pumpChat(tester, targetUserId: null);

    final Finder rows = find.byType(GfConversationRow);
    expect(rows, findsNWidgets(2));
    for (int index = 0; index < 2; index++) {
      final Finder avatarFinder = find.descendant(
        of: rows.at(index),
        matching: find.byType(GfAvatar),
      );
      expect(avatarFinder, findsOneWidget);
      expectCircularAvatar(tester, avatarFinder, size: 40, ring: true);
    }
  });

  testWidgets('both DM message directions keep circular 32px avatars', (
    tester,
  ) async {
    await pumpChat(
      tester,
      messages: <ChatMessagePayload>[
        makeChatMessage(1),
        makeChatMessage(2).copyWith(isSelf: true),
      ],
    );

    final Finder avatars = find.byType(GfAvatar);
    expect(avatars, findsNWidgets(3), reason: 'app bar + peer row + self row');

    Finder? header;
    final List<Finder> messageAvatars = <Finder>[];
    for (int index = 0; index < avatars.evaluate().length; index++) {
      final Finder finder = avatars.at(index);
      if (tester.widget<GfAvatar>(finder).size == 32) {
        messageAvatars.add(finder);
      } else {
        header = finder;
      }
    }

    expect(header, isNotNull);
    expectCircularAvatar(tester, header!, size: 36, ring: true);

    // `ring` distinguishes the directions: only the outgoing avatar carries
    // the base-100 ring (messages_page.dart `_MessageRow`).
    expect(messageAvatars, hasLength(2));
    for (final Finder finder in messageAvatars) {
      final bool isSelf = tester.widget<GfAvatar>(finder).ring;
      expectCircularAvatar(tester, finder, size: 32, ring: isSelf);
    }

    final Finder peerAvatar = messageAvatars.singleWhere(
      (Finder finder) => !tester.widget<GfAvatar>(finder).ring,
    );
    final Finder selfAvatar = messageAvatars.singleWhere(
      (Finder finder) => tester.widget<GfAvatar>(finder).ring,
    );
    final double screenWidth = tester
        .getSize(find.byType(Scaffold).first)
        .width;
    expect(tester.getCenter(peerAvatar).dx, lessThan(screenWidth / 2));
    expect(tester.getCenter(selfAvatar).dx, greaterThan(screenWidth / 2));
  });
}
