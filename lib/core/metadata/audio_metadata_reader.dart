import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;

class AudioMetadata {
  final String title;
  final String artist;
  final String album;
  final String? albumArtPath;

  const AudioMetadata({
    required this.title,
    required this.artist,
    required this.album,
    this.albumArtPath,
  });
}

class AudioMetadataReader {
  /// Reads metadata (Title, Artist, Album, Album Art) from an audio file.
  /// Supports ID3v2, ID3v1, and smart filename fallback.
  static Future<AudioMetadata> read(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      return _fallbackFromFilename(filePath);
    }

    String? title;
    String? artist;
    String? album;
    String? albumArtPath;

    try {
      final ext = p.extension(filePath).toLowerCase();

      if (ext == '.mp3') {
        final id3v2Data = await _readId3v2(file);
        if (id3v2Data != null) {
          title = id3v2Data['title'];
          artist = id3v2Data['artist'];
          album = id3v2Data['album'];
          final artBytes = id3v2Data['artBytes'] as Uint8List?;
          if (artBytes != null && artBytes.isNotEmpty) {
            albumArtPath = await _cacheAlbumArt(filePath, artBytes);
          }
        }

        // If title or artist missing, try ID3v1
        if ((title == null || title.isEmpty) || (artist == null || artist.isEmpty)) {
          final id3v1Data = await _readId3v1(file);
          if (id3v1Data != null) {
            title ??= id3v1Data['title'];
            artist ??= id3v1Data['artist'];
            album ??= id3v1Data['album'];
          }
        }
      }
    } catch (_) {}

    // Check directory for companion album cover images if no embedded art was found
    albumArtPath ??= await _findDirectoryAlbumArt(filePath);

    // Clean up title noise
    if (title != null && title.isNotEmpty) {
      title = _cleanTitle(title);
    }

    // Fallback to filename parsing if title or artist are still missing
    final fallback = _fallbackFromFilename(filePath);
    return AudioMetadata(
      title: (title != null && title.trim().isNotEmpty) ? title.trim() : fallback.title,
      artist: (artist != null && artist.trim().isNotEmpty) ? artist.trim() : fallback.artist,
      album: (album != null && album.trim().isNotEmpty) ? album.trim() : fallback.album,
      albumArtPath: albumArtPath,
    );
  }

  /// Parses ID3v2 tags (ID3v2.3 and ID3v2.4)
  static Future<Map<String, dynamic>?> _readId3v2(File file) async {
    RandomAccessFile? raf;
    try {
      raf = await file.open(mode: FileMode.read);
      final header = await raf.read(10);
      if (header.length < 10) return null;

      // Header must start with 'ID3'
      if (header[0] != 0x49 || header[1] != 0x44 || header[2] != 0x33) {
        return null;
      }

      final version = header[3]; // 3 for ID3v2.3, 4 for ID3v2.4
      // Tag size is 7-bit synchsafe integer
      final tagSize = (header[6] << 21) | (header[7] << 14) | (header[8] << 7) | header[9];

      final readLimit = tagSize.clamp(0, 5 * 1024 * 1024); // max 5MB tag header
      final tagBytes = await raf.read(readLimit);

      String? title;
      String? artist;
      String? album;
      Uint8List? artBytes;

      int pos = 0;
      while (pos + 10 < tagBytes.length) {
        final frameId = String.fromCharCodes(tagBytes.sublist(pos, pos + 4));
        if (!RegExp(r'^[A-Z0-9]{4}$').hasMatch(frameId)) {
          break; // padding reached
        }

        int frameSize;
        if (version == 4) {
          // ID3v2.4 syncsafe
          frameSize = (tagBytes[pos + 4] << 21) |
              (tagBytes[pos + 5] << 14) |
              (tagBytes[pos + 6] << 7) |
              tagBytes[pos + 7];
        } else {
          // ID3v2.3 standard integer
          frameSize = (tagBytes[pos + 4] << 24) |
              (tagBytes[pos + 5] << 16) |
              (tagBytes[pos + 6] << 8) |
              tagBytes[pos + 7];
        }

        if (frameSize <= 0 || pos + 10 + frameSize > tagBytes.length) {
          break;
        }

        final frameData = tagBytes.sublist(pos + 10, pos + 10 + frameSize);

        if (frameId == 'TIT2' && frameData.isNotEmpty) {
          title = _decodeTextFrame(frameData);
        } else if ((frameId == 'TPE1' || frameId == 'TPE2') && frameData.isNotEmpty) {
          artist ??= _decodeTextFrame(frameData);
        } else if (frameId == 'TALB' && frameData.isNotEmpty) {
          album = _decodeTextFrame(frameData);
        } else if (frameId == 'APIC' && frameData.length > 5) {
          artBytes = _extractApicImage(frameData);
        }

        pos += 10 + frameSize;
      }

      return {
        'title': title,
        'artist': artist,
        'album': album,
        'artBytes': artBytes,
      };
    } catch (_) {
      return null;
    } finally {
      await raf?.close();
    }
  }

  static String _decodeTextFrame(Uint8List frameData) {
    final enc = frameData[0];
    final payload = frameData.sublist(1);
    try {
      if (enc == 3) {
        // UTF-8
        return utf8.decode(payload, allowMalformed: true).replaceAll('\x00', '').trim();
      } else if (enc == 1 || enc == 2) {
        // UTF-16
        return _decodeUtf16(payload).replaceAll('\x00', '').trim();
      } else {
        // ISO-8859-1 (Latin1)
        return latin1.decode(payload).replaceAll('\x00', '').trim();
      }
    } catch (_) {
      return latin1.decode(payload).replaceAll('\x00', '').trim();
    }
  }

  static String _decodeUtf16(Uint8List bytes) {
    if (bytes.length < 2) return '';
    // Strip BOM if present
    int start = 0;
    bool isLittleEndian = true;
    if (bytes[0] == 0xFF && bytes[1] == 0xFE) {
      isLittleEndian = true;
      start = 2;
    } else if (bytes[0] == 0xFE && bytes[1] == 0xFF) {
      isLittleEndian = false;
      start = 2;
    }

    final codeUnits = <int>[];
    for (int i = start; i + 1 < bytes.length; i += 2) {
      final codeUnit = isLittleEndian
          ? (bytes[i + 1] << 8) | bytes[i]
          : (bytes[i] << 8) | bytes[i + 1];
      if (codeUnit != 0) {
        codeUnits.add(codeUnit);
      }
    }
    return String.fromCharCodes(codeUnits);
  }

  static Uint8List? _extractApicImage(Uint8List frameData) {
    try {
      int pos = 1; // skip encoding byte
      // Find end of MIME type
      while (pos < frameData.length && frameData[pos] != 0) {
        pos++;
      }
      pos++; // skip null terminator
      if (pos >= frameData.length) return null;

      pos++; // skip picture type byte
      if (pos >= frameData.length) return null;

      // Skip description (can be null-terminated in 1 byte or 2 bytes for utf16)
      while (pos < frameData.length && frameData[pos] != 0) {
        pos++;
      }
      pos++; // skip null
      while (pos < frameData.length && frameData[pos] == 0) {
        pos++;
      }

      if (pos < frameData.length) {
        return Uint8List.fromList(frameData.sublist(pos));
      }
    } catch (_) {}
    return null;
  }

  /// Parses ID3v1 tags (last 128 bytes of file)
  static Future<Map<String, String>?> _readId3v1(File file) async {
    RandomAccessFile? raf;
    try {
      final len = await file.length();
      if (len < 128) return null;

      raf = await file.open(mode: FileMode.read);
      await raf.setPosition(len - 128);
      final bytes = await raf.read(128);
      if (bytes.length < 128) return null;

      if (bytes[0] == 0x54 && bytes[1] == 0x41 && bytes[2] == 0x47) {
        // 'TAG'
        final title = latin1.decode(bytes.sublist(3, 33)).replaceAll('\x00', '').trim();
        final artist = latin1.decode(bytes.sublist(33, 63)).replaceAll('\x00', '').trim();
        final album = latin1.decode(bytes.sublist(63, 93)).replaceAll('\x00', '').trim();
        return {'title': title, 'artist': artist, 'album': album};
      }
    } catch (_) {
      return null;
    } finally {
      await raf?.close();
    }
    return null;
  }

  /// Caches embedded album art bytes to a temporary local image file
  static Future<String?> _cacheAlbumArt(String audioPath, Uint8List artBytes) async {
    try {
      final tempDir = Directory.systemTemp;
      final cacheDir = Directory(p.join(tempDir.path, 'monocoustic_cache'));
      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
      }

      final hash = audioPath.hashCode.abs().toString();
      final artFile = File(p.join(cacheDir.path, 'art_$hash.jpg'));
      await artFile.writeAsBytes(artBytes);
      return artFile.path;
    } catch (_) {
      return null;
    }
  }

  /// Looks for companion album art files in the song's directory
  static Future<String?> _findDirectoryAlbumArt(String audioPath) async {
    try {
      final dir = p.dirname(audioPath);
      final candidates = ['cover.jpg', 'cover.png', 'folder.jpg', 'album.jpg', 'front.jpg'];
      for (final name in candidates) {
        final f = File(p.join(dir, name));
        if (await f.exists()) return f.path;
      }
    } catch (_) {}
    return null;
  }

  /// Cleans up common noise from song titles (like '(Official Music Video)', '_256k')
  static String _cleanTitle(String rawTitle) {
    var title = rawTitle;
    title = title.replaceAll(
      RegExp(r'\s*[\(\[](?:official\s*(?:music\s*)?video|video|audio|lyrics|official|remastered|hq|hd|live|visualizer|lyric\s*video)[^\)\]]*[\)\]]', caseSensitive: false),
      '',
    );
    title = title.replaceAll(RegExp(r'_\d{2,3}k$', caseSensitive: false), '');
    return title.trim();
  }

  /// Fallback parsing from filename if ID3 tags are missing
  static AudioMetadata _fallbackFromFilename(String filePath) {
    final baseName = p.basenameWithoutExtension(filePath);
    String artist = 'Unknown Artist';
    String title = baseName;

    // Check if filename is in "Artist - Title" format
    if (baseName.contains(' - ')) {
      final parts = baseName.split(' - ');
      artist = parts[0].trim();
      title = parts.sublist(1).join(' - ').trim();
    }

    title = _cleanTitle(title);

    return AudioMetadata(
      title: title.isNotEmpty ? title : baseName,
      artist: artist,
      album: 'Local Music',
    );
  }
}
