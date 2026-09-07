import 'package:core/core.dart';
import '../../../l10n/app_localizations.dart';

/// Same template/event semantics as Web NotificationsPage. Protocol keys are
/// never user-facing fallback copy; older literal titles remain supported.
(String, String) notificationText(
  NotificationPayload item,
  AppLocalizations l10n,
) {
  String literal(String? value) {
    final text = (value ?? '').trim();
    return text.startsWith('notifications.') ? '' : text;
  }

  final actor =
      [
            item.actor.username,
            item.payload.actorName,
            item.payload.metadata?.followerName,
          ]
          .map(literal)
          .firstWhere(
            (s) => s.isNotEmpty,
            orElse: () => l10n.notificationSomeone,
          );
  final key = item.payload.templateKey ?? '';
  final event = switch (key) {
    'notifications.templates.comment' => 'comment',
    'notifications.templates.postReply' => 'post_reply',
    'notifications.templates.topicPost' => 'topic_post',
    'notifications.templates.follow' => 'follow',
    'notifications.templates.badge' => 'badge',
    'notifications.templates.like' => 'like',
    'notifications.templates.wikiUpdated' => 'wiki_updated',
    _ => item.eventType,
  };
  final badge = literal(item.payload.metadata?.badgeName);
  final title = switch (event) {
    'comment' => l10n.notificationComment(actor),
    'post_reply' => l10n.notificationPostReply(actor),
    'topic_post' => l10n.notificationTopicPost(actor),
    'follow' => l10n.notificationFollow(actor),
    'like' => l10n.notificationLike(actor),
    'wiki_updated' => l10n.notificationWikiUpdated(actor),
    'badge' =>
      badge.isEmpty
          ? l10n.notificationBadgeUnnamed
          : l10n.notificationBadge(badge),
    _ =>
      [item.title, item.payload.title]
          .map(literal)
          .firstWhere((s) => s.isNotEmpty, orElse: () => l10n.notificationNew),
  };
  final subtitle =
      [
            item.topic?.title,
            item.payload.topicTitle,
            item.content,
            item.payload.content,
            item.payload.templateParams?.preview,
          ]
          .map(literal)
          .firstWhere((s) => s.isNotEmpty && s != title, orElse: () => '');
  return (title, subtitle);
}
