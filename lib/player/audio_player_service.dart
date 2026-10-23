import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../core/lyrics/lyrics_manager.dart';
import '../core/metadata/audio_metadata_reader.dart';
import '../core/models/lyric_line.dart';
import '../core/models/playback_state.dart';
import '../core/models/remote_protocol.dart';
import '../core/models/song.dart';
import '../server/local_music_server.dart';

class AudioPlayerService extends ChangeNotifier {
  final AudioPlayer _player = AudioPlayer();
  final LocalMusicServer _server = LocalMusicServer();

  final List<Song> _queue = [];
  int _currentIndex = -1;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _volume = 1.0;
  bool _isShuffle = false;
  PlaybackRepeatMode _repeatMode = PlaybackRepeatMode.off;
  int _currentLyricIndex = -1;
  String? _savedFolderPath;
  final List<int> _shufflePlayedIndices = [];

  // Sleep timer
  Timer? _sleepTimer;
  int _sleepTimerRemainingSeconds = 0;

  // Subscriptions
  StreamSubscription? _posSub;
  StreamSubscription? _durSub;
  StreamSubscription? _stateSub;
  StreamSubscription? _completeSub;

  AudioPlayerService() {
    _initAudioPlayer();
    _initServer();
  }

  // Getters
  List<Song> get queue => List.unmodifiable(_queue);
  int get currentIndex => _currentIndex;
  Song? get currentSong => (_currentIndex >= 0 && _currentIndex < _queue.length)
      ? _queue[_currentIndex]
      : null;
  bool get isPlaying => _isPlaying;
  Duration get position => _position;
  Duration get duration => _duration;
  double get volume => _volume;
  bool get isShuffle => _isShuffle;
  PlaybackRepeatMode get repeatMode => _repeatMode;
  int get currentLyricIndex => _currentLyricIndex;
  LocalMusicServer get server => _server;
  int get sleepTimerRemainingSeconds => _sleepTimerRemainingSeconds;
  bool get isSleepTimerActive => _sleepTimer != null;
  String? get savedFolderPath => _savedFolderPath;

  PlaybackStateSnapshot get snapshot => PlaybackStateSnapshot(
        currentSong: currentSong,
        isPlaying: _isPlaying,
        position: _position,
        duration: _duration,
        volume: _volume,
        isShuffle: _isShuffle,
        repeatMode: _repeatMode,
        queue: _queue,
        currentIndex: _currentIndex,
        currentLyricIndex: _currentLyricIndex,
      );

  void _initAudioPlayer() {
    _player.setVolume(_volume);

    _posSub = _player.onPositionChanged.listen((pos) {
      _position = pos;
      final song = currentSong;
      if (song != null && song.lyrics.isNotEmpty) {
        final newLyricIdx = LyricsManager.findActiveIndex(song.lyrics, pos);
        if (newLyricIdx != _currentLyricIndex) {
          _currentLyricIndex = newLyricIdx;
          notifyListeners();
        }
      }
      _server.broadcastPosition(pos.inMilliseconds, _currentLyricIndex);
      notifyListeners();
    });

    _durSub = _player.onDurationChanged.listen((dur) {
      _duration = dur;
      notifyListeners();
      _server.broadcastFullState(snapshot);
    });

    _stateSub = _player.onPlayerStateChanged.listen((state) {
      final playing = (state == PlayerState.playing);
      if (_isPlaying != playing) {
        _isPlaying = playing;
        notifyListeners();
        _server.broadcastFullState(snapshot);
      }
    });

    _completeSub = _player.onPlayerComplete.listen((_) {
      _handleTrackCompleted();
    });
  }

  void _initServer() {
    _server.getStateSnapshot = () => snapshot;
    _server.onCommandReceived = _handleRemoteCommand;
  }

  Future<int> startServer({int port = 8080}) async {
    final boundPort = await _server.start(port: port);
    notifyListeners();
    return boundPort;
  }

  Future<void> stopServer() async {
    await _server.stop();
    notifyListeners();
  }

  void _handleRemoteCommand(String command, Map<String, dynamic>? data) {
    switch (command) {
      case RemoteProtocol.cmdPlay:
        resume();
        break;
      case RemoteProtocol.cmdPause:
        pause();
        break;
      case RemoteProtocol.cmdTogglePlay:
        togglePlay();
        break;
      case RemoteProtocol.cmdNext:
        next();
        break;
      case RemoteProtocol.cmdPrevious:
        previous();
        break;
      case RemoteProtocol.cmdSeek:
        if (data != null && data.containsKey('positionMs')) {
          seek(Duration(milliseconds: data['positionMs'] as int));
        }
        break;
      case RemoteProtocol.cmdSetVolume:
        if (data != null && data.containsKey('volume')) {
          setVolume((data['volume'] as num).toDouble());
        }
        break;
      case RemoteProtocol.cmdToggleShuffle:
        toggleShuffle();
        break;
      case RemoteProtocol.cmdToggleRepeat:
        toggleRepeat();
        break;
      case RemoteProtocol.cmdJumpToIndex:
        if (data != null && data.containsKey('index')) {
          playAtIndex(data['index'] as int);
        }
        break;
      case RemoteProtocol.cmdSeekLyric:
        if (data != null && data.containsKey('lineIdx')) {
          seekToLyricLine(data['lineIdx'] as int);
        }
        break;
      case RemoteProtocol.cmdSleepTimer:
        if (data != null && data.containsKey('minutes')) {
          setSleepTimer(data['minutes'] as int);
        }
        break;
    }
  }

  Future<void> addFiles(List<String> filePaths, {bool autoPlay = true}) async {
    final List<Song> newSongs = [];

    for (final path in filePaths) {
      if (_queue.any((s) => s.filePath == path)) continue;
      final metadata = await AudioMetadataReader.read(path);
      // Auto-detect companion .lrc or .smi file
      final lyricFile = await LyricsManager.findCompanionLyricFile(path);
      List<LyricLine> lyrics = [];
      if (lyricFile != null) {
        lyrics = await LyricsManager.loadFromFile(lyricFile);
      }

      newSongs.add(
        Song(
          id: '${DateTime.now().microsecondsSinceEpoch}_${newSongs.length}',
          title: metadata.title,
          artist: metadata.artist,
          album: metadata.album,
          duration: Duration.zero,
          filePath: path,
          lyricPath: lyricFile,
          albumArtPath: metadata.albumArtPath,
          lyrics: lyrics,
        ),
      );
    }

    _queue.addAll(newSongs);

    // If queue was empty, play first song only if autoPlay is requested
    if (autoPlay && _currentIndex == -1 && _queue.isNotEmpty) {
      await playAtIndex(0);
    } else {
      if (_currentIndex == -1 && _queue.isNotEmpty) {
        _currentIndex = 0;
      }
      notifyListeners();
      _server.broadcastFullState(snapshot);
    }
  }

  /// Scans a folder recursively and imports all detected audio files into the library.
  /// Automatically persists the chosen folder path across app restarts.
  Future<void> addFolder(String folderPath, {bool autoPlay = false, bool clearExisting = false}) async {
    final dir = Directory(folderPath);
    if (!await dir.exists()) return;

    _savedFolderPath = folderPath;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('saved_music_folder', folderPath);
    } catch (_) {}

    final audioExtensions = {'.mp3', '.flac', '.wav', '.aac', '.ogg', '.m4a'};
    final List<String> audioFiles = [];

    try {
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          final ext = p.extension(entity.path).toLowerCase();
          if (audioExtensions.contains(ext)) {
            audioFiles.add(entity.path);
          }
        }
      }
    } catch (_) {}

    if (audioFiles.isNotEmpty) {
      audioFiles.sort();
      if (clearExisting) {
        _queue.clear();
        _currentIndex = -1;
        _shufflePlayedIndices.clear();
      }
      await addFiles(audioFiles, autoPlay: autoPlay);
    }
  }

  /// Restores the previously selected music folder on app launch
  Future<void> restoreSavedLibrary() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('saved_music_folder');
      if (saved != null && saved.isNotEmpty) {
        final dir = Directory(saved);
        if (await dir.exists()) {
          _savedFolderPath = saved;
          await addFolder(saved, autoPlay: false, clearExisting: true);
        }
      }
    } catch (_) {}
  }

  Future<void> setCustomLyrics(int songIndex, String lyricFilePath) async {
    if (songIndex < 0 || songIndex >= _queue.length) return;
    final lyrics = await LyricsManager.loadFromFile(lyricFilePath);
    _queue[songIndex] = _queue[songIndex].copyWith(
      lyricPath: lyricFilePath,
      lyrics: lyrics,
    );

    if (songIndex == _currentIndex) {
      _currentLyricIndex = LyricsManager.findActiveIndex(lyrics, _position);
    }

    notifyListeners();
    _server.broadcastFullState(snapshot);
  }

  Future<void> playAtIndex(int index) async {
    if (index < 0 || index >= _queue.length) return;
    _currentIndex = index;
    _currentLyricIndex = -1;
    _position = Duration.zero;

    final song = _queue[index];

    // Check if companion lyric exists if not loaded yet
    if (song.lyrics.isEmpty) {
      final companionLyric = await LyricsManager.findCompanionLyricFile(song.filePath);
      if (companionLyric != null) {
        final parsedLyrics = await LyricsManager.loadFromFile(companionLyric);
        _queue[index] = song.copyWith(lyricPath: companionLyric, lyrics: parsedLyrics);
      }
    }

    await _player.stop();
    await _player.play(DeviceFileSource(song.filePath));
    _isPlaying = true;

    notifyListeners();
    _server.broadcastFullState(snapshot);
  }

  Future<void> togglePlay() async {
    if (_isPlaying) {
      await pause();
    } else {
      await resume();
    }
  }

  Future<void> pause() async {
    await _player.pause();
    _isPlaying = false;
    notifyListeners();
    _server.broadcastFullState(snapshot);
  }

  Future<void> resume() async {
    if (_currentIndex == -1 && _queue.isNotEmpty) {
      await playAtIndex(0);
      return;
    }
    await _player.resume();
    _isPlaying = true;
    notifyListeners();
    _server.broadcastFullState(snapshot);
  }

  Future<void> next() async {
    if (_queue.isEmpty) return;

    // Shuffle playback: picks unplayed tracks in queue
    if (_isShuffle && _queue.length > 1) {
      if (!_shufflePlayedIndices.contains(_currentIndex) && _currentIndex >= 0) {
        _shufflePlayedIndices.add(_currentIndex);
      }
      if (_shufflePlayedIndices.length >= _queue.length) {
        _shufflePlayedIndices.clear();
        if (_repeatMode == PlaybackRepeatMode.off) {
          await _player.stop();
          _isPlaying = false;
          _position = Duration.zero;
          notifyListeners();
          _server.broadcastFullState(snapshot);
          return;
        }
      }

      final unplayed = List<int>.generate(_queue.length, (i) => i)
          .where((i) => !_shufflePlayedIndices.contains(i))
          .toList();

      final nextIdx = unplayed.isNotEmpty
          ? unplayed[Random().nextInt(unplayed.length)]
          : Random().nextInt(_queue.length);

      await playAtIndex(nextIdx);
      return;
    }

    if (_currentIndex + 1 < _queue.length) {
      await playAtIndex(_currentIndex + 1);
    } else if (_repeatMode == PlaybackRepeatMode.all) {
      await playAtIndex(0);
    } else {
      await _player.stop();
      _isPlaying = false;
      _position = Duration.zero;
      notifyListeners();
      _server.broadcastFullState(snapshot);
    }
  }

  Future<void> previous() async {
    if (_queue.isEmpty) return;

    // If more than 3 seconds in, restart track
    if (_position.inSeconds > 3) {
      await seek(Duration.zero);
      return;
    }

    if (_currentIndex > 0) {
      await playAtIndex(_currentIndex - 1);
    } else if (_repeatMode == PlaybackRepeatMode.all) {
      await playAtIndex(_queue.length - 1);
    } else {
      await seek(Duration.zero);
    }
  }

  Future<void> seek(Duration target) async {
    await _player.seek(target);
    _position = target;
    final song = currentSong;
    if (song != null && song.lyrics.isNotEmpty) {
      _currentLyricIndex = LyricsManager.findActiveIndex(song.lyrics, target);
    }
    notifyListeners();
    _server.broadcastPosition(target.inMilliseconds, _currentLyricIndex);
  }

  void seekToLyricLine(int lineIndex) {
    final song = currentSong;
    if (song == null || lineIndex < 0 || lineIndex >= song.lyrics.length) return;
    final line = song.lyrics[lineIndex];
    seek(line.timestamp);
  }

  Future<void> setVolume(double val) async {
    _volume = val.clamp(0.0, 1.0);
    await _player.setVolume(_volume);
    notifyListeners();
    _server.broadcastFullState(snapshot);
  }

  void toggleShuffle() {
    _isShuffle = !_isShuffle;
    _shufflePlayedIndices.clear();
    notifyListeners();
    _server.broadcastFullState(snapshot);
  }

  void toggleRepeat() {
    switch (_repeatMode) {
      case PlaybackRepeatMode.off:
        _repeatMode = PlaybackRepeatMode.all;
        break;
      case PlaybackRepeatMode.all:
        _repeatMode = PlaybackRepeatMode.one;
        break;
      case PlaybackRepeatMode.one:
        _repeatMode = PlaybackRepeatMode.off;
        break;
    }
    notifyListeners();
    _server.broadcastFullState(snapshot);
  }

  void removeSong(int index) {
    if (index < 0 || index >= _queue.length) return;
    _queue.removeAt(index);
    if (_currentIndex == index) {
      if (_queue.isEmpty) {
        _currentIndex = -1;
        _player.stop();
      } else {
        _currentIndex = _currentIndex.clamp(0, _queue.length - 1);
        playAtIndex(_currentIndex);
      }
    } else if (_currentIndex > index) {
      _currentIndex--;
    }
    notifyListeners();
    _server.broadcastFullState(snapshot);
  }

  void clearQueue() {
    _queue.clear();
    _currentIndex = -1;
    _position = Duration.zero;
    _duration = Duration.zero;
    _player.stop();
    notifyListeners();
    _server.broadcastFullState(snapshot);
  }

  void _handleTrackCompleted() {
    if (_repeatMode == PlaybackRepeatMode.one) {
      seek(Duration.zero);
      resume();
    } else {
      next();
    }
  }

  /// Sets a sleep timer in minutes (0 cancels the timer)
  void setSleepTimer(int minutes) {
    _sleepTimer?.cancel();
    _sleepTimer = null;

    if (minutes <= 0) {
      _sleepTimerRemainingSeconds = 0;
      notifyListeners();
      return;
    }

    _sleepTimerRemainingSeconds = minutes * 60;
    notifyListeners();

    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_sleepTimerRemainingSeconds > 0) {
        _sleepTimerRemainingSeconds--;
        notifyListeners();
      } else {
        timer.cancel();
        _sleepTimer = null;
        pause();
      }
    });
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel();
    _stateSub?.cancel();
    _completeSub?.cancel();
    _sleepTimer?.cancel();
    _player.dispose();
    _server.stop();
    super.dispose();
  }
}
