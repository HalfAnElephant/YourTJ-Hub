import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:core/core.dart';
import 'package:ui_kit/ui_kit.dart';

import '../../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../navigation/tab_scroll_registry.dart';
import '../../server_messages.dart';
import '../../widgets/skeletons.dart';
import '../../widgets/status_views.dart';
import '../../widgets/topic_list.dart';
import '../../widgets/root_surface.dart';

/// 首页:公告 + 话题流(web HomePage.vue 的移动端形态)。
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  static const String _feedModeKey = 'goose:home-feed-mode';

  AsyncValue<HomeProps> _page = const AsyncValue.loading();
  String _sort = '';
  final List<TopicPayload> _topics = <TopicPayload>[];
  bool _loadingMore = false;
  GfTopicFeedMode _feedMode = GfTopicFeedMode.card;
  final GfScrollToTopController _scrollToTopController =
      GfScrollToTopController();
  late final GfTabScrollRegistry _tabScrollRegistry;

  @override
  void initState() {
    super.initState();
    _tabScrollRegistry = ref.read(tabScrollRegistryProvider)
      ..register(GfShellDestination.home, _scrollToTopController);
    _restoreFeedMode();
    _load();
  }

  @override
  void dispose() {
    _tabScrollRegistry.unregister(
      GfShellDestination.home,
      _scrollToTopController,
    );
    super.dispose();
  }

  Future<void> _restoreFeedMode() async {
    try {
      final SharedPreferences preferences =
          await SharedPreferences.getInstance();
      final String? stored = preferences.getString(_feedModeKey);
      if (!mounted || stored == null) return;
      setState(() {
        _feedMode = GfTopicFeedMode.values.firstWhere(
          (GfTopicFeedMode mode) => mode.name == stored,
          orElse: () => GfTopicFeedMode.card,
        );
      });
    } catch (_) {
      // Restricted storage keeps the web-compatible mobile default: card.
    }
  }

  Future<void> _setFeedMode(GfTopicFeedMode mode) async {
    if (_feedMode == mode) return;
    setState(() => _feedMode = mode);
    try {
      final SharedPreferences preferences =
          await SharedPreferences.getInstance();
      await preferences.setString(_feedModeKey, mode.name);
    } catch (_) {
      // The in-memory choice remains valid for this session.
    }
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _page = const AsyncValue.loading());
    try {
      final PagePayload payload = await ref
          .read(pageRepositoryProvider)
          .home(sort: _sort);
      if (!mounted) return;
      final HomeProps? props = parsePageProps<HomeProps>(payload);
      if (props == null) {
        setState(
          () => _page = AsyncValue.error(
            AppLocalizations.of(context).commonParseFailed,
            StackTrace.current,
          ),
        );
        return;
      }
      setState(() {
        _page = AsyncValue.data(props);
        _topics.clear();
        _topics.addAll(props.topics);
      });
    } catch (e, st) {
      if (!mounted) return;
      setState(() => _page = AsyncValue.error(e, st));
    }
  }

  Future<void> _loadMore() async {
    final HomeProps? props = _page.value;
    if (props == null || !props.pagination.hasNext || _loadingMore) return;
    final String nextUrl = props.pagination.nextUrl;
    if (nextUrl.isEmpty) return;
    setState(() => _loadingMore = true);
    try {
      // 真实分页:按后端 nextUrl 请求下一页(页面级数据通道)。
      final PagePayload payload = await ref
          .read(pageRepositoryProvider)
          .fetch(nextUrl);
      if (!mounted) return;
      final HomeProps? next = parsePageProps<HomeProps>(payload);
      if (next != null && next.topics.isNotEmpty) {
        setState(() {
          _topics.addAll(next.topics);
          _page = AsyncValue.data(next);
        });
      }
    } catch (_) {
      // 加载更多失败静默(用户可再次点击)。
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _switchSort(String sort) {
    if (sort == _sort) return;
    _sort = sort;
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return RootSurface(
      title: 'YourTJ',
      actions: [
        IconButton(
          tooltip: l10n.commonSearch,
          icon: const GfSymbol('search'),
          onPressed: () => context.push('/search'),
        ),
      ],
      toolbarHeight: 44,
      toolbar: _page.hasValue
          ? _HomeToolbar(
              props: _page.requireValue,
              selected: _sort,
              feedMode: _feedMode,
              onSelected: _switchSort,
              onFeedModeSelected: _setFeedMode,
            )
          : const SizedBox.shrink(),
      body: (top, bottom) => _page.when(
        loading: () => Padding(
          padding: EdgeInsets.only(top: top),
          child: const GfTopicFeedSkeleton(),
        ),
        error: (e, _) =>
            GfErrorRetry(message: resolveErrorMessage(l10n, e), onRetry: _load),
        data: (props) => GfScrollToTop(
          semanticLabel: l10n.commonBackToTop,
          controller: _scrollToTopController,
          showButton: false,
          builder: (_, controller) => RefreshIndicator(
            onRefresh: () => _load(silent: true),
            child: GfTopicList(
              controller: controller,
              padding: EdgeInsets.only(top: top, bottom: bottom),
              header: _AnnouncementBanner(props: props),
              loading: _loadingMore,
              topics: _topics,
              feedMode: _feedMode,
              hasMore: props.pagination.hasNext,
              onLoadMore: _loadMore,
            ),
          ),
        ),
      ),
    );
  }
}

/// 公告横幅:多条公告自动轮播(PageView + Timer),单条静态展示。
class _AnnouncementBanner extends ConsumerStatefulWidget {
  const _AnnouncementBanner({required this.props});

  final HomeProps props;

  @override
  ConsumerState<_AnnouncementBanner> createState() =>
      _AnnouncementBannerState();
}

class _AnnouncementBannerState extends ConsumerState<_AnnouncementBanner> {
  static const Duration _interval = Duration(seconds: 5);

  final PageController _controller = PageController();
  Timer? _timer;
  int _current = 0;

  @override
  void initState() {
    super.initState();
    final items = widget.props.announcement.items ?? const [];
    if (items.length > 1) {
      // 自动轮播:每 5s 切到下一条,循环。
      _timer = Timer.periodic(_interval, (_) {
        if (!mounted || !_controller.hasClients) return;
        final int next = (_current + 1) % items.length;
        _controller.animateToPage(
          next,
          duration: GfMotion.content,
          curve: GfMotion.standardEase,
        );
        _current = next;
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.props.announcement.enabled) return const SizedBox.shrink();
    final items = widget.props.announcement.items ?? const [];
    if (items.isEmpty) return const SizedBox.shrink();
    final GfColors colors = GfTheme.colorsOf(context);

    // 对齐 web 公告面板(gf-panel + primary/15 边框 + primary/5 渐变底)。
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.05),
        border: Border(
          bottom: BorderSide(color: colors.primary.withValues(alpha: 0.15)),
        ),
      ),
      child: items.length == 1
          ? _bannerText(colors, items.first.title)
          : SizedBox(
              height: 38,
              child: Stack(
                children: [
                  PageView.builder(
                    controller: _controller,
                    itemCount: items.length,
                    onPageChanged: (i) => setState(() => _current = i),
                    itemBuilder: (context, i) =>
                        _bannerText(colors, items[i].title),
                  ),
                  // 轮播指示点(web active bg-primary)。
                  Positioned(
                    right: 10,
                    bottom: 5,
                    child: Row(
                      children: [
                        for (int i = 0; i < items.length; i++)
                          Container(
                            width: i == _current ? 14 : 6,
                            height: 4,
                            margin: const EdgeInsets.only(left: 3),
                            decoration: BoxDecoration(
                              color: i == _current
                                  ? colors.primary
                                  : colors.baseContent.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _bannerText(GfColors colors, String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GfTheme.typographyOf(
            context,
          ).small.copyWith(color: colors.primary),
        ),
      ),
    );
  }
}

class _HomeToolbar extends ConsumerWidget {
  const _HomeToolbar({
    required this.props,
    required this.selected,
    required this.feedMode,
    required this.onSelected,
    required this.onFeedModeSelected,
  });

  final HomeProps props;
  final String selected;
  final GfTopicFeedMode feedMode;
  final ValueChanged<String> onSelected;
  final ValueChanged<GfTopicFeedMode> onFeedModeSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 选中项:显式 selected 优先;为空时回退到服务端标记的 active tab。
    String effective = selected;
    if (effective.isEmpty) {
      for (final tab in props.tabs) {
        if (tab.active) {
          effective = tab.key;
          break;
        }
      }
    }
    final AppLocalizations l10n = AppLocalizations.of(context);
    final GfColors colors = GfTheme.colorsOf(context);

    // Mobile keeps the Web information hierarchy in one compact row: sort
    // tabs on the left and the list/card view switch on the right. Publishing
    // already has a persistent center entry in the bottom navigation.
    return Container(
      color: colors.base100,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Expanded(
            child: GfTabBar(
              tabs: <GfTab>[
                for (final tab in props.tabs)
                  GfTab(
                    // 后端 tabs[].label 可能为空(web 端按 key fallback 到
                    // i18n),空 label 会让选中态深色底渲染成黑块,必须兜底。
                    label: _sortTabLabel(context, tab.key, tab.label ?? ''),
                    value: tab.key,
                  ),
              ],
              selected: effective,
              onSelected: (Object value) => onSelected(value as String),
            ),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<GfTopicFeedMode>(
            tooltip: l10n.topicFeedModeList,
            icon: const GfSymbol('sliders-horizontal', size: 20),
            onSelected: onFeedModeSelected,
            itemBuilder: (_) => [
              PopupMenuItem(
                value: GfTopicFeedMode.list,
                child: Text(l10n.topicFeedModeList),
              ),
              PopupMenuItem(
                value: GfTopicFeedMode.card,
                child: Text(l10n.topicFeedModeCard),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 排序 tab 文案:与 web `sortTabLabel(key, label)` 一致——后端 label
  /// 为空时按 key 回退到 i18n(最新/热门/流行)。
  String _sortTabLabel(BuildContext context, String key, String label) {
    if (label.isNotEmpty) return label;
    final AppLocalizations l10n = AppLocalizations.of(context);
    return switch (key) {
      'latest' => l10n.sortLatest,
      'hot' => l10n.sortHot,
      'popular' => l10n.sortPopular,
      _ => key,
    };
  }
}
