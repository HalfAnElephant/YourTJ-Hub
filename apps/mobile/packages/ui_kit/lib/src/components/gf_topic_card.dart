import 'package:flutter/material.dart';

import '../theme/gf_theme.dart';
import 'atoms/gf_avatar.dart';
import 'gf_card.dart';
import 'gf_chip.dart';
import 'gf_topic_row.dart';
import 'gf_image_viewer.dart';

/// Mobile topic-feed card aligned with the web `TopicFeedPreview` surface.
class GfTopicCard extends StatefulWidget {
  const GfTopicCard({
    super.key,
    required this.title,
    required this.description,
    required this.authorName,
    required this.authorAvatarUrl,
    required this.categories,
    required this.imageUrls,
    required this.activityText,
    required this.replyCount,
    required this.viewCount,
    this.onTap,
    this.imageAspectRatio,
    this.pinned = false,
    this.unseen = false,
    this.hot = false,
  });

  final String title;
  final String description;
  final String authorName;
  final String authorAvatarUrl;
  final List<GfTopicCategory> categories;
  final List<String> imageUrls;
  final String activityText;
  final int replyCount;
  final int viewCount;
  final VoidCallback? onTap;

  /// Optional known first-image ratio; otherwise decoded from the image stream.
  final double? imageAspectRatio;
  final bool pinned;
  final bool unseen;
  final bool hot;

  @override
  State<GfTopicCard> createState() => _GfTopicCardState();
}

class _GfTopicCardState extends State<GfTopicCard> {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  double _ratio = 1.5;
  String? _observedUrl;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _observeImage();
  }

  @override
  void didUpdateWidget(GfTopicCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _observeImage();
  }

  void _observeImage() {
    final url = widget.imageUrls.where((url) => url.isNotEmpty).firstOrNull;
    if (url == _observedUrl) return;
    if (_listener != null) _stream?.removeListener(_listener!);
    _observedUrl = url;
    _ratio = 1.5;
    if (url == null) return;
    _stream = NetworkImage(url).resolve(createLocalImageConfiguration(context));
    _listener = ImageStreamListener((info, synchronousCall) {
      try {
        if (!mounted || info.image.height == 0) return;
        final ratio = info.image.width / info.image.height;
        if (synchronousCall) {
          _ratio = ratio;
        } else {
          setState(() => _ratio = ratio);
        }
      } finally {
        info.dispose();
      }
    }, onError: (Object error, StackTrace? stack) {});
    _stream!.addListener(_listener!);
  }

  @override
  void dispose() {
    if (_listener != null) _stream?.removeListener(_listener!);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final GfColors colors = GfTheme.colorsOf(context);
    final allImages = widget.imageUrls.where((url) => url.isNotEmpty).toList();
    final images = allImages.take(3).toList();
    final ratio = widget.imageAspectRatio ?? _ratio;
    final portrait = ratio < 1;
    final singleImage = images.length == 1 && portrait;

    Widget photo(int index, {double? width, double height = 104}) =>
        GestureDetector(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  GfImageViewer(images: allImages, initialIndex: index),
            ),
          ),
          child: _TopicImage(
            url: images[index],
            width: width,
            height: height,
            fit: portrait ? BoxFit.cover : BoxFit.contain,
          ),
        );

    final Widget textContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _AuthorMeta(
          name: widget.authorName,
          avatarUrl: widget.authorAvatarUrl,
          activityText: widget.activityText,
          categories: widget.categories,
          hot: widget.hot,
          pinned: widget.pinned,
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          widget.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.baseContent,
                            fontSize: 17,
                            height: 1.45,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (widget.unseen) ...<Widget>[
                        const SizedBox(width: 6),
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(top: 7),
                          decoration: BoxDecoration(
                            color: colors.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (widget.description.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(
                      widget.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.baseContent.withValues(alpha: 0.85),
                        fontSize: 17,
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (singleImage) ...<Widget>[
              const SizedBox(width: 12),
              photo(0, width: 108, height: 132),
            ],
          ],
        ),
        if (images.isNotEmpty && !singleImage) ...<Widget>[
          const SizedBox(height: 4),
          LayoutBuilder(
            builder: (context, constraints) {
              if (images.length == 1) {
                return photo(
                  0,
                  width: constraints.maxWidth,
                  height: (constraints.maxWidth / ratio).clamp(96.0, 240.0),
                );
              }
              if (!portrait && images.length > 2) {
                return SizedBox(
                  height: 190,
                  child: Stack(
                    children: [
                      for (int i = images.length - 1; i >= 0; i--)
                        Positioned(
                          left: i * 18,
                          right: (2 - i) * 18,
                          top: i * 12,
                          bottom: (2 - i) * 12,
                          child: photo(i, height: 166),
                        ),
                      Positioned(
                        right: 10,
                        bottom: 8,
                        child: _ImageCount(count: allImages.length),
                      ),
                    ],
                  ),
                );
              }
              return Row(
                children: [
                  for (int i = 0; i < images.length; i++) ...[
                    if (i > 0) const SizedBox(width: 6),
                    Expanded(
                      child: Stack(
                        children: [
                          photo(
                            i,
                            width: double.infinity,
                            height: portrait
                                ? 132
                                : ((constraints.maxWidth - 6) / 2 / ratio)
                                      .clamp(72.0, 160.0),
                          ),
                          if (i == images.length - 1 && allImages.length > 3)
                            Positioned(
                              right: 6,
                              bottom: 6,
                              child: _ImageCount(count: allImages.length),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ],
        const SizedBox(height: 4),
        Row(
          children: <Widget>[
            _Metric(
              icon: Icons.chat_bubble_outline,
              value: '${widget.replyCount}',
            ),
            const SizedBox(width: 6),
            _Metric(
              icon: Icons.visibility_outlined,
              value: '${widget.viewCount}',
            ),
          ],
        ),
      ],
    );

    return GfCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      onTap: widget.onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GfAvatar(src: widget.authorAvatarUrl, size: 36),
          const SizedBox(width: 10),
          Expanded(child: textContent),
        ],
      ),
    );
  }
}

class _AuthorMeta extends StatelessWidget {
  const _AuthorMeta({
    required this.name,
    required this.avatarUrl,
    required this.activityText,
    required this.categories,
    required this.hot,
    required this.pinned,
  });

  final String name;
  final String avatarUrl;
  final String activityText;
  final List<GfTopicCategory> categories;
  final bool hot;
  final bool pinned;

  @override
  Widget build(BuildContext context) {
    final GfColors colors = GfTheme.colorsOf(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Flexible(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.baseContent,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      activityText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.baseContent.withValues(alpha: 0.55),
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
              if (categories.isNotEmpty || hot) ...<Widget>[
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    for (final GfTopicCategory category in categories)
                      GfChip(label: category.name, color: category.color),
                    if (hot)
                      Container(
                        height: 20,
                        padding: const EdgeInsets.symmetric(horizontal: 7),
                        decoration: BoxDecoration(
                          color: colors.warning.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(
                              Icons.auto_awesome,
                              size: 12,
                              color: colors.warning,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              'hot',
                              style: TextStyle(
                                color: colors.warning,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        if (pinned) Icon(Icons.push_pin, size: 16, color: colors.error),
      ],
    );
  }
}

class _TopicImage extends StatelessWidget {
  const _TopicImage({
    required this.url,
    this.width,
    required this.height,
    this.fit = BoxFit.cover,
  });

  final String url;
  final double? width;
  final double height;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final GfColors colors = GfTheme.colorsOf(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: width,
        height: height,
        child: Image.network(
          url,
          fit: fit,
          errorBuilder:
              (BuildContext context, Object error, StackTrace? stack) {
                return ColoredBox(
                  color: colors.base200,
                  child: Icon(Icons.image_outlined, color: colors.iconMuted),
                );
              },
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    final GfColors colors = GfTheme.colorsOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 16, color: colors.iconMuted),
          const SizedBox(width: 5),
          Text(
            value,
            style: TextStyle(
              color: colors.baseContent.withValues(alpha: 0.55),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _ImageCount extends StatelessWidget {
  const _ImageCount({required this.count});
  final int count;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.65),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.photo_library_outlined,
            size: 12,
            color: Colors.white,
          ),
          const SizedBox(width: 4),
          Text(
            '$count',
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    ),
  );
}
