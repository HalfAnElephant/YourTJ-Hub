import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

import '../helpers.dart';

/// Verifies the rendered clip geometry rather than one node's configuration:
/// every clip path applied to the avatar — inside [GfAvatar] and from any
/// ancestor wrapper — must accept 24 sample points on the avatar's inscribed
/// circle (95% of the radius, in global coordinates). A circular clip accepts
/// all of them; a polygon clip — for example the repo's historical six-point
/// hexagon clipper — rejects the directions that fall outside its edges
/// (issue #877 review).
void expectCircularClipGeometry(WidgetTester tester, Finder avatarFinder) {
  final RenderObject avatar = tester.renderObject(avatarFinder);
  final Rect avatarRect = tester.getRect(avatarFinder);
  final List<RenderClipPath> clips = <RenderClipPath>[];

  void collect(RenderObject node) {
    if (node is RenderClipPath && node.clipper != null) clips.add(node);
    node.visitChildren(collect);
  }

  collect(avatar);
  for (RenderObject? node = avatar.parent; node != null; node = node.parent) {
    if (node is RenderClipPath && node.clipper != null) clips.add(node);
  }

  expect(clips, isNotEmpty, reason: 'the avatar must be clipped');
  final double radius = avatarRect.size.shortestSide / 2 * 0.95;
  for (final RenderClipPath clipNode in clips) {
    final Path clip = clipNode.clipper!
        .getClip(clipNode.size)
        .transform(clipNode.getTransformTo(null).storage);
    for (int step = 0; step < 24; step++) {
      final double angle = step * math.pi / 12;
      final Offset point =
          avatarRect.center + Offset(math.cos(angle), math.sin(angle)) * radius;
      expect(
        clip.contains(point),
        isTrue,
        reason:
            'every clip over the avatar must accept the inscribed circle; '
            '${clipNode.runtimeType} rejects $point (${step * 15}°)',
      );
    }
  }
}

/// Asserts the shared circular-avatar contract: the decoration is a circle,
/// the child is clipped to it, neither size nor ring drifts, and the painted
/// region really is circular.
///
/// Regression guard for issue #877 (DM avatars reported as hexagons): the
/// clip shape must survive every avatar refactor.
void expectCircularAvatar(
  WidgetTester tester,
  Finder avatarFinder, {
  required double size,
  required bool ring,
}) {
  final GfAvatar avatar = tester.widget<GfAvatar>(avatarFinder);
  expect(avatar.size, size);
  expect(avatar.ring, ring);

  final Finder containerFinder = find
      .descendant(of: avatarFinder, matching: find.byType(Container))
      .first;
  final Container container = tester.widget<Container>(containerFinder);
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
  expect(
    find.descendant(of: avatarFinder, matching: find.byType(CustomPaint)),
    findsNothing,
    reason:
        'a custom painter inside the avatar could draw a non-circular shape',
  );
  expectCircularClipGeometry(tester, avatarFinder);
}

void main() {
  testWidgets('GfAvatar keeps every DM size circular and clipped', (
    tester,
  ) async {
    await tester.pumpWidget(
      gfApp(
        const Column(
          children: <Widget>[
            GfAvatar(src: '', size: 32),
            GfAvatar(src: '', size: 36, ring: true),
            GfAvatar(src: '', size: 40, ring: true),
          ],
        ),
      ),
    );

    expectCircularAvatar(
      tester,
      find.byType(GfAvatar).at(0),
      size: 32,
      ring: false,
    );
    expectCircularAvatar(
      tester,
      find.byType(GfAvatar).at(1),
      size: 36,
      ring: true,
    );
    expectCircularAvatar(
      tester,
      find.byType(GfAvatar).at(2),
      size: 40,
      ring: true,
    );
  });

  testWidgets('GfAvatar clips a loaded image to the circular decoration', (
    tester,
  ) async {
    await tester.pumpWidget(
      gfApp(const GfAvatar(src: 'https://example.test/avatar.png', size: 32)),
    );

    final Finder avatarFinder = find.byType(GfAvatar);
    expectCircularAvatar(tester, avatarFinder, size: 32, ring: false);
    expect(
      find.descendant(of: avatarFinder, matching: find.byType(Image)),
      findsOneWidget,
    );
  });

  testWidgets('conversation list row keeps the circular 40px ring avatar', (
    tester,
  ) async {
    await tester.pumpWidget(
      gfApp(
        const SizedBox(
          width: 320,
          child: GfConversationRow(
            avatarUrl: '',
            name: 'Bob',
            lastMessage: '你好',
            time: '10:30',
            unreadCount: 0,
          ),
        ),
      ),
    );

    final Finder avatarFinder = find.descendant(
      of: find.byType(GfConversationRow),
      matching: find.byType(GfAvatar),
    );
    expect(avatarFinder, findsOneWidget);
    expectCircularAvatar(tester, avatarFinder, size: 40, ring: true);
  });
}
