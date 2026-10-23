import '../models/lyric_line.dart';

class SmiParser {
  /// Regular expression to match `<SYNC Start=####>` tags.
  /// Handles attributes with or without quotes, case-insensitive.
  static final RegExp _syncTagRegex = RegExp(
    r'<SYNC\s+[^>]*Start=["' "'" r']?(\d+)["' "'" r']?[^>]*>',
    caseSensitive: false,
  );

  /// Regular expression to match `<P Class=...>` blocks.
  static final RegExp _pClassRegex = RegExp(
    r'<P\s+[^>]*Class=["' "'" r']?([a-zA-Z0-9_-]+)["' "'" r']?[^>]*>(.*?)(?=<P|\s*$)',
    caseSensitive: false,
    dotAll: true,
  );

  /// HTML entities to replace
  static final Map<String, String> _htmlEntities = {
    '&nbsp;': ' ',
    '&amp;': '&',
    '&lt;': '<',
    '&gt;': '>',
    '&quot;': '"',
    '&#39;': "'",
    '&apos;': "'",
  };

  /// Clean HTML markup and decode basic entities.
  static String cleanHtml(String html) {
    var text = html;

    // Replace <br> and <br/> with space
    text = text.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), ' ');

    // Strip all HTML tags
    text = text.replaceAll(RegExp(r'<[^>]+>'), '');

    // Decode HTML entities
    _htmlEntities.forEach((entity, replacement) {
      text = text.replaceAll(RegExp(RegExp.escape(entity), caseSensitive: false), replacement);
    });

    // Collapse multiple whitespace
    text = text.replaceAll(RegExp(r'[ \t]+'), ' ').trim();

    return text;
  }

  /// Parse the raw SAMI (.smi) text into a list of sorted [LyricLine]s.
  static List<LyricLine> parse(String content) {
    if (content.trim().isEmpty) return [];

    final List<LyricLine> result = [];
    final syncMatches = _syncTagRegex.allMatches(content).toList();
    if (syncMatches.isEmpty) return [];

    // Temporary map of timestamp_ms -> list of (class, text)
    final Map<int, List<_SmiEntry>> entriesByTime = {};

    for (int i = 0; i < syncMatches.length; i++) {
      final currentMatch = syncMatches[i];
      final startMs = int.tryParse(currentMatch.group(1) ?? '0') ?? 0;

      // Determine text slice until next <SYNC> or end
      final startIndex = currentMatch.end;
      final endIndex = (i + 1 < syncMatches.length)
          ? syncMatches[i + 1].start
          : content.length;

      final rawSlice = content.substring(startIndex, endIndex);

      // Check if there are explicit <P Class=...> definitions
      final pMatches = _pClassRegex.allMatches(rawSlice).toList();
      if (pMatches.isNotEmpty) {
        for (final pMatch in pMatches) {
          final className = pMatch.group(1) ?? '';
          final pContent = cleanHtml(pMatch.group(2) ?? '');
          entriesByTime.putIfAbsent(startMs, () => []).add(
                _SmiEntry(className: className, text: pContent),
              );
        }
      } else {
        // No <P Class=...>, direct text
        final cleaned = cleanHtml(rawSlice);
        entriesByTime.putIfAbsent(startMs, () => []).add(
              _SmiEntry(className: '', text: cleaned),
            );
      }
    }

    final sortedTimes = entriesByTime.keys.toList()..sort();

    for (final timeMs in sortedTimes) {
      final entries = entriesByTime[timeMs]!;
      if (entries.isEmpty) continue;

      // Extract main text (first non-empty or first item)
      final primary = entries.first;
      String mainText = primary.text;
      String? translation;

      if (entries.length > 1) {
        // Look for alternate language class as translation
        final nonPrimary = entries.skip(1).firstWhere(
              (e) => e.text.isNotEmpty && e.text != mainText,
              orElse: () => const _SmiEntry(className: '', text: ''),
            );
        if (nonPrimary.text.isNotEmpty) {
          translation = nonPrimary.text;
        }
      }

      result.add(
        LyricLine(
          timestamp: Duration(milliseconds: timeMs),
          text: mainText,
          translation: translation,
        ),
      );
    }

    return result;
  }
}

class _SmiEntry {
  final String className;
  final String text;

  const _SmiEntry({required this.className, required this.text});
}
