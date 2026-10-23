import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/lyric_line.dart';
import 'lrc_parser.dart';
import 'smi_parser.dart';

class LyricsManager {
  /// Loads lyrics from file content or detects format based on extension.
  static List<LyricLine> parseContent(String content, {String? extension}) {
    final ext = extension?.toLowerCase();
    if (ext == '.smi' || ext == '.sami' || content.contains('<SYNC') || content.contains('<SAMI>')) {
      return SmiParser.parse(content);
    } else {
      return LrcParser.parse(content);
    }
  }

  /// Attempts to automatically discover a matching .lrc or .smi file for a given audio file path.
  static Future<String?> findCompanionLyricFile(String audioFilePath) async {
    final dir = p.dirname(audioFilePath);
    final baseName = p.basenameWithoutExtension(audioFilePath);

    final lrcCandidate = p.join(dir, '$baseName.lrc');
    if (await File(lrcCandidate).exists()) return lrcCandidate;

    final smiCandidate = p.join(dir, '$baseName.smi');
    if (await File(smiCandidate).exists()) return smiCandidate;

    final samiCandidate = p.join(dir, '$baseName.sami');
    if (await File(samiCandidate).exists()) return samiCandidate;

    return null;
  }

  /// Loads lyrics from a given file path.
  static Future<List<LyricLine>> loadFromFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return [];

    try {
      final content = await file.readAsString();
      return parseContent(content, extension: p.extension(filePath));
    } catch (_) {
      // In case of non-UTF8 encoding (e.g. EUC-KR for Korean SMI files or Windows-1252),
      // we can attempt latin1 fallback
      try {
        final bytes = await file.readAsBytes();
        final content = String.fromCharCodes(bytes);
        return parseContent(content, extension: p.extension(filePath));
      } catch (_) {
        return [];
      }
    }
  }

  /// Binary search to find current active lyric index for a given position in milliseconds.
  /// Returns -1 if playback is before the first lyric line.
  static int findActiveIndex(List<LyricLine> lyrics, Duration position) {
    if (lyrics.isEmpty) return -1;
    final posMs = position.inMilliseconds;

    if (posMs < lyrics.first.timestamp.inMilliseconds) {
      return -1;
    }

    int low = 0;
    int high = lyrics.length - 1;
    int result = -1;

    while (low <= high) {
      final mid = (low + high) >> 1;
      final midMs = lyrics[mid].timestamp.inMilliseconds;

      if (midMs <= posMs) {
        result = mid;
        low = mid + 1; // Try to find a later line that also qualifies
      } else {
        high = mid - 1;
      }
    }

    return result;
  }
}
