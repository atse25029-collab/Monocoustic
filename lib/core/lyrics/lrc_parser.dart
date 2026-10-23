import '../models/lyric_line.dart';

class LrcParser {
  /// Regular expression to match one or more timestamps at the beginning of a line.
  /// Matches [mm:ss.xx], [mm:ss:xx], [mm:ss.xxx], [m:ss.xx]
  static final RegExp _timestampRegex =
      RegExp(r'\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]');

  /// Regular expression to match offset tag: [offset:+/-ms]
  static final RegExp _offsetRegex =
      RegExp(r'\[offset:\s*([+-]?\d+)\]', caseSensitive: false);

  /// Parse the raw LRC text into a list of sorted [LyricLine]s.
  static List<LyricLine> parse(String content) {
    if (content.trim().isEmpty) return [];

    final lines = content.split(RegExp(r'\r?\n'));
    int offsetMs = 0;

    // Check for offset tag in headers
    for (final line in lines) {
      final offsetMatch = _offsetRegex.firstMatch(line.trim());
      if (offsetMatch != null) {
        offsetMs = int.tryParse(offsetMatch.group(1) ?? '0') ?? 0;
        break;
      }
    }

    final List<LyricLine> parsedLyrics = [];

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      // Skip non-timestamp metadata tags like [ti:Title], [ar:Artist], etc.
      if (trimmed.startsWith('[') && !trimmed.startsWith(_timestampRegex)) {
        continue;
      }

      final matches = _timestampRegex.allMatches(trimmed).toList();
      if (matches.isEmpty) continue;

      // Extract lyric text after the last timestamp match
      var text = trimmed.substring(matches.last.end).trim();
      // Clean HTML tags or entities if embedded
      text = text.replaceAll(RegExp(r'<[^>]+>'), '');
      text = text
          .replaceAll('&nbsp;', ' ')
          .replaceAll('&amp;', '&')
          .replaceAll('&quot;', '"')
          .replaceAll('&apos;', "'")
          .replaceAll('&#39;', "'");
      text = text.replaceAll(RegExp(r'[ \t]+'), ' ').trim();

      for (final match in matches) {
        final minutes = int.parse(match.group(1)!);
        final seconds = int.parse(match.group(2)!);
        final fractionStr = match.group(3) ?? '0';

        int milliseconds = 0;
        if (fractionStr.length == 1) {
          milliseconds = int.parse(fractionStr) * 100;
        } else if (fractionStr.length == 2) {
          milliseconds = int.parse(fractionStr) * 10;
        } else if (fractionStr.length >= 3) {
          milliseconds = int.parse(fractionStr.substring(0, 3));
        }

        var totalMs = (minutes * 60 * 1000) + (seconds * 1000) + milliseconds;
        totalMs += offsetMs;
        if (totalMs < 0) totalMs = 0;

        parsedLyrics.add(
          LyricLine(
            timestamp: Duration(milliseconds: totalMs),
            text: text,
          ),
        );
      }
    }

    // Sort chronologically
    parsedLyrics.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    return parsedLyrics;
  }
}
