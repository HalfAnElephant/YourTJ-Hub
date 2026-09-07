import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

import '../../l10n/app_localizations.dart';

/// Changes action only after scrolling settles, preventing a moving tap target.
/// The controller belongs to the page; nested horizontal galleries are ignored.
class ContextualFab extends StatefulWidget {
  const ContextualFab({
    super.key,
    required this.controller,
    required this.child,
    required this.onPrimary,
    required this.onRefresh,
    this.reply = false,
    this.onReturnToTop,
    this.discussionKey,
    this.visible = true,
    this.bottom = 16,
  });
  final ScrollController controller;
  final Widget child;
  final VoidCallback onPrimary;
  final Future<void> Function() onRefresh;
  final bool reply;
  final Future<void> Function()? onReturnToTop;
  final GlobalKey? discussionKey;
  final bool visible;
  final double bottom;

  @override
  State<ContextualFab> createState() => _ContextualFabState();
}

enum _Action { primary, refresh, top, discussion }

class _ContextualFabState extends State<ContextualFab> {
  Timer? _settle;
  double _offset = 0;
  bool _towardTop = false;
  bool _returnedToTop = false;
  bool _busy = false;
  _Action _action = _Action.primary;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(ContextualFab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onScroll);
      widget.controller.addListener(_onScroll);
      _offset = 0;
    }
  }

  @override
  void dispose() {
    _settle?.cancel();
    widget.controller.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    if (!widget.controller.hasClients || _busy) return;
    final position = widget.controller.position;
    final offset = position.pixels.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((offset - _offset).abs() < 2) return;
    _towardTop = offset < _offset;
    _offset = offset;
    if (offset > 40) _returnedToTop = false;
    _settle?.cancel();
    _settle = Timer(const Duration(milliseconds: 260), () {
      if (!mounted) return;
      final target = widget.discussionKey?.currentContext?.findRenderObject();
      final longFirstPost =
          target is RenderBox &&
          target.hasSize &&
          target.localToGlobal(Offset.zero).dy >
              MediaQuery.sizeOf(context).height &&
          _offset > MediaQuery.sizeOf(context).height * 0.7;
      setState(
        () => _action = _towardTop
            ? (widget.reply && _offset > 40 ? _Action.top : _Action.refresh)
            : (widget.reply && longFirstPost
                  ? _Action.discussion
                  : _Action.primary),
      );
    });
  }

  Future<void> _activate() async {
    if (_busy) return;
    if (_action == _Action.primary) {
      widget.onPrimary();
      return;
    }
    setState(() => _busy = true);
    try {
      if (_action == _Action.discussion) {
        final target = widget.discussionKey?.currentContext;
        if (target != null) {
          await Scrollable.ensureVisible(
            target,
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : GfMotion.standard,
          );
        }
      } else {
        if (_action == _Action.top) await widget.onReturnToTop?.call();
        if (!mounted) return;
        if (widget.controller.hasClients) {
          await widget.controller.animateTo(
            0,
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : GfMotion.standard,
            curve: Curves.easeOutCubic,
          );
        }
        if (_action == _Action.refresh) await widget.onRefresh();
        _returnedToTop = true;
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _action = _returnedToTop ? _Action.refresh : _Action.primary;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final (icon, label) = switch (_action) {
      _Action.primary => (
        widget.reply ? Icons.reply_rounded : Icons.add_rounded,
        widget.reply ? l10n.topicReplyHint : l10n.navPublish,
      ),
      _Action.refresh => (Icons.refresh_rounded, l10n.fabRefresh),
      _Action.top => (Icons.vertical_align_top_rounded, l10n.commonBackToTop),
      _Action.discussion => (
        Icons.vertical_align_bottom_rounded,
        l10n.fabDiscussion,
      ),
    };
    return Stack(
      children: [
        Positioned.fill(child: widget.child),
        if (widget.visible)
          Positioned(
            right: 16,
            bottom: widget.bottom,
            child: FloatingActionButton(
              heroTag: null,
              tooltip: label,
              onPressed: _busy ? null : _activate,
              child: _busy
                  ? const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(icon),
            ),
          ),
      ],
    );
  }
}
