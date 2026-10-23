import 'song.dart';

enum PlaybackRepeatMode { off, all, one }

class PlaybackStateSnapshot {
  final Song? currentSong;
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final double volume;
  final bool isShuffle;
  final PlaybackRepeatMode repeatMode;
  final List<Song> queue;
  final int currentIndex;
  final int currentLyricIndex;

  const PlaybackStateSnapshot({
    this.currentSong,
    this.isPlaying = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.volume = 1.0,
    this.isShuffle = false,
    this.repeatMode = PlaybackRepeatMode.off,
    this.queue = const [],
    this.currentIndex = -1,
    this.currentLyricIndex = -1,
  });

  PlaybackStateSnapshot copyWith({
    Song? currentSong,
    bool? isPlaying,
    Duration? position,
    Duration? duration,
    double? volume,
    bool? isShuffle,
    PlaybackRepeatMode? repeatMode,
    List<Song>? queue,
    int? currentIndex,
    int? currentLyricIndex,
    bool clearSong = false,
  }) {
    return PlaybackStateSnapshot(
      currentSong: clearSong ? null : (currentSong ?? this.currentSong),
      isPlaying: isPlaying ?? this.isPlaying,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      volume: volume ?? this.volume,
      isShuffle: isShuffle ?? this.isShuffle,
      repeatMode: repeatMode ?? this.repeatMode,
      queue: queue ?? this.queue,
      currentIndex: currentIndex ?? this.currentIndex,
      currentLyricIndex: currentLyricIndex ?? this.currentLyricIndex,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'currentSong': currentSong?.toJson(),
      'isPlaying': isPlaying,
      'positionMs': position.inMilliseconds,
      'durationMs': duration.inMilliseconds,
      'volume': volume,
      'isShuffle': isShuffle,
      'repeatMode': repeatMode.name,
      'queue': queue.map((s) => s.toJson()).toList(),
      'currentIndex': currentIndex,
      'currentLyricIndex': currentLyricIndex,
    };
  }

  factory PlaybackStateSnapshot.fromJson(Map<String, dynamic> json) {
    return PlaybackStateSnapshot(
      currentSong: json['currentSong'] != null
          ? Song.fromJson(json['currentSong'] as Map<String, dynamic>)
          : null,
      isPlaying: json['isPlaying'] as bool? ?? false,
      position: Duration(milliseconds: json['positionMs'] as int? ?? 0),
      duration: Duration(milliseconds: json['durationMs'] as int? ?? 0),
      volume: (json['volume'] as num?)?.toDouble() ?? 1.0,
      isShuffle: json['isShuffle'] as bool? ?? false,
      repeatMode: PlaybackRepeatMode.values.firstWhere(
        (m) => m.name == json['repeatMode'],
        orElse: () => PlaybackRepeatMode.off,
      ),
      queue: (json['queue'] as List<dynamic>?)
              ?.map((e) => Song.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      currentIndex: json['currentIndex'] as int? ?? -1,
      currentLyricIndex: json['currentLyricIndex'] as int? ?? -1,
    );
  }
}
