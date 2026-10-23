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

  /// Clean HTML markup and decode all entities (named, decimal, hex).
  static String cleanHtml(String html) {
    var text = html;

    // Strip bracketed timestamps that some tools prepend (e.g. [00:15.00])
    text = text.replaceAll(RegExp(r'\[\d{1,2}:\d{2}(?:[.:]\d{1,3})?\]'), '');

    // Replace <br> and <br/> with space
    text = text.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), ' ');

    // Strip all HTML tags
    text = text.replaceAll(RegExp(r'<[^>]+>'), '');

    // Common named entities
    text = text
        .replaceAll(RegExp(r'&nbsp;', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'&amp;', caseSensitive: false), '&')
        .replaceAll(RegExp(r'&lt;', caseSensitive: false), '<')
        .replaceAll(RegExp(r'&gt;', caseSensitive: false), '>')
        .replaceAll(RegExp(r'&quot;', caseSensitive: false), '"')
        .replaceAll(RegExp(r'&apos;', caseSensitive: false), "'");

    // Decimal entities: &#39; &#34; etc.
    text = text.replaceAllMapped(RegExp(r'&#(\d+);'), (match) {
      final code = int.tryParse(match.group(1)!);
      return code != null ? String.fromCharCode(code) : match.group(0)!;
    });

    // Hex entities: &#x27; etc.
    text = text.replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (match) {
      final code = int.tryParse(match.group(1)!, radix: 16);
      return code != null ? String.fromCharCode(code) : match.group(0)!;
    });

    // Collapse multiple whitespace
    text = text.replaceAll(RegExp(r'[ \t]+'), ' ').trim();

    return text;
  }

  /// Parse the raw SAMI (.smi) text into a list of sorted [LyricLine]s.
  static List<LyricLine> parse(String content) {
    if (content.trim().isEmpty) return [];

    // Strip line-prefixed bracketed timestamps first so they don't leak into slices
    final sanitizedContent = content.replaceAll(RegExp(r'^\s*\[\d{1,2}:\d{2}(?:[.:]\d{1,3})?\]\s*', multiLine: true), '');

    final List<LyricLine> result = [];
    final syncMatches = _syncTagRegex.allMatches(sanitizedContent).toList();
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
          : sanitizedContent.length;

      final rawSlice = sanitizedContent.substring(startIndex, endIndex);

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

      // Filter out entries that are purely empty or whitespace if non-empty entries exist at this timestamp
      final nonEmptyEntries = entries.where((e) => e.text.trim().isNotEmpty).toList();

      String mainText = '';
      String? translation;

      if (nonEmptyEntries.isNotEmpty) {
        mainText = nonEmptyEntries.first.text;
        if (nonEmptyEntries.length > 1) {
          final nonPrimary = nonEmptyEntries.skip(1).firstWhere(
                (e) => e.text.isNotEmpty && e.text != mainText,
                orElse: () => const _SmiEntry(className: '', text: ''),
              );
          if (nonPrimary.text.isNotEmpty) {
            translation = nonPrimary.text;
          }
        }
      } else {
        // All were empty/silence marker (e.g. &nbsp;)
        mainText = '';
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
