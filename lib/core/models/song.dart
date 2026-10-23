import 'lyric_line.dart';

class Song {
  final String id;
  final String title;
  final String artist;
  final String album;
  final Duration duration;
  final String filePath;
  final String? lyricPath;
  final String? albumArtPath;
  final List<LyricLine> lyrics;

  const Song({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    required this.filePath,
    this.lyricPath,
    this.albumArtPath,
    this.lyrics = const [],
  });

  Song copyWith({
    String? id,
    String? title,
    String? artist,
    String? album,
    Duration? duration,
    String? filePath,
    String? lyricPath,
    String? albumArtPath,
    List<LyricLine>? lyrics,
  }) {
    return Song(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      duration: duration ?? this.duration,
      filePath: filePath ?? this.filePath,
      lyricPath: lyricPath ?? this.lyricPath,
      albumArtPath: albumArtPath ?? this.albumArtPath,
      lyrics: lyrics ?? this.lyrics,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'album': album,
      'durationMs': duration.inMilliseconds,
      'filePath': filePath,
      'lyricPath': lyricPath,
      'albumArtPath': albumArtPath,
      'lyrics': lyrics.map((l) => l.toJson()).toList(),
    };
  }

  factory Song.fromJson(Map<String, dynamic> json) {
    return Song(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? 'Unknown Title',
      artist: json['artist'] as String? ?? 'Unknown Artist',
      album: json['album'] as String? ?? 'Unknown Album',
      duration: Duration(milliseconds: json['durationMs'] as int? ?? 0),
      filePath: json['filePath'] as String? ?? '',
      lyricPath: json['lyricPath'] as String?,
      albumArtPath: json['albumArtPath'] as String?,
      lyrics: (json['lyrics'] as List<dynamic>?)
              ?.map((e) => LyricLine.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }
}
