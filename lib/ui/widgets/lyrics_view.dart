import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/models/lyric_line.dart';

class LyricsView extends StatefulWidget {
  final List<LyricLine> lyrics;
  final int activeIndex;
  final ValueChanged<int>? onLineTap;
  final bool isCompact;

  const LyricsView({
    super.key,
    required this.lyrics,
    required this.activeIndex,
    this.onLineTap,
    this.isCompact = false,
  });

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _lineKeys = {};
  bool _userIsScrolling = false;
  Timer? _resumeAutoScrollTimer;

  @override
  void didUpdateWidget(covariant LyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.activeIndex != oldWidget.activeIndex && !_userIsScrolling) {
      _scrollToActiveLine();
    }
  }

  void _scrollToActiveLine() {
    if (widget.activeIndex < 0 || widget.activeIndex >= widget.lyrics.length) {
      return;
    }

    final key = _lineKeys[widget.activeIndex];
    final context = key?.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(
        context,
        alignment: 0.4, // Keep active line around upper-middle
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _onUserScrollStart() {
    _userIsScrolling = true;
    _resumeAutoScrollTimer?.cancel();
    // Resume auto scrolling after 3.5 seconds of user inactivity
    _resumeAutoScrollTimer = Timer(const Duration(milliseconds: 3500), () {
      if (mounted) {
        setState(() {
          _userIsScrolling = false;
        });
        _scrollToActiveLine();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _resumeAutoScrollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.lyrics.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.music_note_outlined,
              size: widget.isCompact ? 40 : 64,
              color: Colors.white24,
            ),
            const SizedBox(height: 12),
            Text(
              'No lyrics available',
              style: TextStyle(
                color: Colors.white38,
                fontSize: widget.isCompact ? 14 : 16,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Load a companion .lrc or .smi file',
              style: TextStyle(
                color: Colors.white24,
                fontSize: widget.isCompact ? 11 : 12,
              ),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification is ScrollStartNotification &&
                notification.dragDetails != null) {
              _onUserScrollStart();
            }
            return false;
          },
          child: ListView.builder(
            controller: _scrollController,
            padding: EdgeInsets.symmetric(
              vertical: widget.isCompact ? 60 : 120,
              horizontal: widget.isCompact ? 16 : 32,
            ),
            itemCount: widget.lyrics.length,
            itemBuilder: (context, index) {
              final line = widget.lyrics[index];
              final isActive = (index == widget.activeIndex);
              final key = _lineKeys.putIfAbsent(index, () => GlobalKey());

              // Skip empty text silence markers unless it's the active one
              if (line.text.isEmpty && !isActive) {
                return const SizedBox(height: 16);
              }

              return Padding(
                key: key,
                padding: EdgeInsets.symmetric(
                  vertical: widget.isCompact ? 6 : 12,
                ),
                child: InkWell(
                  onTap: () => widget.onLineTap?.call(index),
                  borderRadius: BorderRadius.circular(12),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    padding: EdgeInsets.symmetric(
                      vertical: widget.isCompact ? 6 : 10,
                      horizontal: widget.isCompact ? 8 : 16,
                    ),
                    decoration: BoxDecoration(
                      color: isActive
                          ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.15)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: isActive
                          ? Border.all(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withValues(alpha: 0.4),
                              width: 1,
                            )
                          : null,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          line.text.isEmpty ? '•••' : line.text,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: widget.isCompact
                                ? (isActive ? 17 : 14)
                                : (isActive ? 24 : 18),
                            fontWeight:
                                isActive ? FontWeight.bold : FontWeight.w500,
                            color: isActive
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.35),
                            height: 1.3,
                            shadows: isActive
                                ? [
                                    Shadow(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary
                                          .withValues(alpha: 0.6),
                                      blurRadius: 16,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                        if (line.translation != null &&
                            line.translation!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            line.translation!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: widget.isCompact
                                  ? (isActive ? 13 : 11)
                                  : (isActive ? 16 : 13),
                              fontStyle: FontStyle.italic,
                              color: isActive
                                  ? Theme.of(context)
                                      .colorScheme
                                      .primaryContainer
                                  : Colors.white24,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),

        // Indicator when user has manually scrolled away
        if (_userIsScrolling)
          Positioned(
            bottom: 16,
            right: 16,
            child: FloatingActionButton.small(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
              tooltip: 'Sync with playback',
              onPressed: () {
                setState(() {
                  _userIsScrolling = false;
                });
                _scrollToActiveLine();
              },
              child: const Icon(Icons.vertical_align_center, size: 20),
            ),
          ),
      ],
    );
  }
}
