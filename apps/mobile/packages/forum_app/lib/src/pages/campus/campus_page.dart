import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ui_kit/ui_kit.dart';

import '../../../l10n/app_localizations.dart';

/// A stable campus destination keeps study tools one tap from the community.
class CampusPage extends StatelessWidget {
  const CampusPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = GfTheme.colorsOf(context);
    return Scaffold(
      appBar: GfAppBar(
        title: Text(l10n.navCampus),
        automaticallyImplyLeading: false,
        actions: [
          GfIconButton(
            icon: Icons.search_outlined,
            tooltip: l10n.commonSearch,
            onPressed: () => context.push('/search'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 96),
        children: [
          Text(
            l10n.campusTitle,
            style: TextStyle(
              fontSize: 28,
              height: 1.25,
              fontWeight: FontWeight.w700,
              color: colors.baseContent,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.campusSubtitle,
            style: TextStyle(
              fontSize: 15,
              height: 1.6,
              color: colors.iconMuted,
            ),
          ),
          const SizedBox(height: 28),
          for (final entry in <(IconData, String, String, String, Color)>[
            (
              Icons.school_outlined,
              l10n.coursesTitle,
              l10n.campusCoursesHint,
              '/courses',
              colors.primary,
            ),
            (
              Icons.calendar_month_outlined,
              l10n.scheduleTitle,
              l10n.campusScheduleHint,
              '/schedule',
              colors.success,
            ),
            (
              Icons.auto_stories_outlined,
              l10n.wikiTitle,
              l10n.campusWikiHint,
              '/wiki',
              colors.warning,
            ),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: GfCard(
                emphasized: true,
                onTap: () => context.push(entry.$4),
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: entry.$5.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(entry.$1, color: entry.$5, size: 28),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.$2,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: colors.baseContent,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            entry.$3,
                            style: TextStyle(
                              color: colors.iconMuted,
                              fontSize: 13,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 20,
                      color: colors.iconMuted,
                    ),
                  ],
                ),
              ),
            ),
          TextButton.icon(
            onPressed: () => context.push('/about'),
            icon: const Icon(Icons.info_outline, size: 18),
            label: Text(l10n.siteInfoTitle),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: null,
        tooltip: l10n.navPublish,
        onPressed: () => context.push('/publish?type=2'),
        child: const Icon(Icons.add),
      ),
    );
  }
}
