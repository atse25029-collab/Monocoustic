import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../core/lyrics/lyrics_manager.dart';
import '../core/models/playback_state.dart';
import '../core/models/remote_protocol.dart';
import 'notification_service.dart';

enum ConnectionStatus { disconnected, connecting, connected, error }

class RemoteClientService extends ChangeNotifier {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  int _connectionAttemptId = 0;

  ConnectionStatus _status = ConnectionStatus.disconnected;
  String _host = '';
  int _port = 8080;
  String? _errorMessage;

  PlaybackStateSnapshot _state = const PlaybackStateSnapshot();

  // Local sleep timer state for display on remote
  int _sleepTimerMinutes = 0;

  // Real-time smooth position interpolation & zero-latency lyrics synchronization
  Timer? _smoothTicker;
  DateTime _lastPositionSyncTime = DateTime.now();
  int _lastPositionSyncMs = 0;

  // Throttled volume sender to prevent network choking during continuous slider dragging
  Timer? _volumeThrottleTimer;
  double? _pendingVolume;

  ConnectionStatus get status => _status;
  bool get isConnected => _status == ConnectionStatus.connected;
  String get host => _host;
  int get port => _port;
  String? get errorMessage => _errorMessage;
  PlaybackStateSnapshot get state => _state;
  int get sleepTimerMinutes => _sleepTimerMinutes;

  RemoteClientService() {
    _initNotificationHandler();
  }

  void _initNotificationHandler() {
    RemoteNotificationService.instance.initialize(
      handler: (actionId) {
        if (actionId == RemoteNotificationService.actionPlayPause) {
          togglePlay();
        } else if (actionId == RemoteNotificationService.actionNext) {
          next();
        } else if (actionId == RemoteNotificationService.actionPrev) {
          previous();
        }
      },
    );
  }

  Future<void> connect(String ipOrHost, {int port = 8080}) async {
    final currentAttempt = ++_connectionAttemptId;

    // Cleanly cancel and close prior attempts
    await _forceCleanup();

    // Clean IP address input (in case user pasted http:// or :port)
    var cleanedHost = ipOrHost.trim();
    if (cleanedHost.startsWith('http://')) {
      cleanedHost = cleanedHost.substring(7);
    } else if (cleanedHost.startsWith('https://')) {
      cleanedHost = cleanedHost.substring(8);
    } else if (cleanedHost.startsWith('ws://')) {
      cleanedHost = cleanedHost.substring(5);
    }

    if (cleanedHost.contains('/')) {
      cleanedHost = cleanedHost.split('/').first;
    }

    var targetPort = port;
    if (cleanedHost.contains(':')) {
      final parts = cleanedHost.split(':');
      cleanedHost = parts[0];
      targetPort = int.tryParse(parts[1]) ?? port;
    }

    _host = cleanedHost;
    _port = targetPort;
    _status = ConnectionStatus.connecting;
    _errorMessage = null;
    notifyListeners();

    try {
      final uri = Uri.parse('ws://$_host:$_port/ws');
      final channel = WebSocketChannel.connect(uri);
      _channel = channel;

      _subscription = channel.stream.listen(
        _handleIncomingMessage,
        onDone: () {
          if (currentAttempt == _connectionAttemptId) {
            _status = ConnectionStatus.disconnected;
            _stopSmoothTicker();
            _safeSetWakelock(false);
            RemoteNotificationService.instance.cancelNotification();
            notifyListeners();
          }
        },
        onError: (e) {
          if (currentAttempt == _connectionAttemptId) {
            _status = ConnectionStatus.error;
            _errorMessage = 'Connection closed: $e';
            _stopSmoothTicker();
            _safeSetWakelock(false);
            RemoteNotificationService.instance.cancelNotification();
            notifyListeners();
          }
        },
        cancelOnError: true,
      );

      // Timeout in 4.5 seconds so we never hang indefinitely on bad IPs
      await channel.ready.timeout(const Duration(milliseconds: 4500));

      // If another connect attempt started in the meantime, discard this one
      if (currentAttempt != _connectionAttemptId) {
        try {
          await channel.sink.close();
        } catch (_) {}
        return;
      }

      _status = ConnectionStatus.connected;
      _errorMessage = null;
      notifyListeners();

      // Enable wakelock when connected so connection isn't throttled in background
      await _safeSetWakelock(true);

      // Start smooth ticker for local zero-latency interpolation
      _startSmoothTicker();

      // Request fresh state immediately
      sendCommand(RemoteProtocol.cmdRequestSync);
    } on TimeoutException {
      if (currentAttempt == _connectionAttemptId) {
        await _forceCleanup();
        _status = ConnectionStatus.error;
        _errorMessage = 'Connection timed out to $_host:$_port. Please verify IP & port and ensure desktop player is running.';
        await _safeSetWakelock(false);
        RemoteNotificationService.instance.cancelNotification();
        notifyListeners();
      }
    } catch (e) {
      if (currentAttempt == _connectionAttemptId) {
        await _forceCleanup();
        _status = ConnectionStatus.error;
        _errorMessage = 'Could not connect to $_host:$_port ($e)';
        await _safeSetWakelock(false);
        RemoteNotificationService.instance.cancelNotification();
        notifyListeners();
      }
    }
  }

  Future<void> _forceCleanup() async {
    _stopSmoothTicker();
    try {
      await _subscription?.cancel();
    } catch (_) {}
    _subscription = null;

    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }

  Future<void> _safeSetWakelock(bool enable) async {
    try {
      if (enable) {
        await WakelockPlus.enable();
      } else {
        await WakelockPlus.disable();
      }
    } catch (_) {}
  }

  void _startSmoothTicker() {
    _smoothTicker?.cancel();
    _smoothTicker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!_state.isPlaying || !isConnected) return;

      final elapsedMs = DateTime.now().difference(_lastPositionSyncTime).inMilliseconds;
      final interpolatedMs = _lastPositionSyncMs + elapsedMs;

      final song = _state.currentSong;
      final newPos = Duration(milliseconds: interpolatedMs);

      int activeLyric = _state.currentLyricIndex;
      if (song != null && song.lyrics.isNotEmpty) {
        activeLyric = LyricsManager.findActiveIndex(song.lyrics, newPos);
      }

      if (newPos != _state.position || activeLyric != _state.currentLyricIndex) {
        _state = _state.copyWith(
          position: newPos,
          currentLyricIndex: activeLyric,
        );
        notifyListeners();
      }
    });
  }

  void _stopSmoothTicker() {
    _smoothTicker?.cancel();
    _smoothTicker = null;
  }

  void _handleIncomingMessage(dynamic raw) {
    if (raw is! String) return;
    final message = RemoteProtocol.decodeMessage(raw);
    if (message == null || message['type'] != 'event') return;

    final event = message['event'] as String? ?? '';
    final data = message['data'];

    if (event == RemoteProtocol.evtFullState && data is Map<String, dynamic>) {
      _state = PlaybackStateSnapshot.fromJson(data);
      _lastPositionSyncMs = _state.position.inMilliseconds;
      _lastPositionSyncTime = DateTime.now();

      notifyListeners();
      _syncBackgroundNotification();
    } else if (event == RemoteProtocol.evtPositionTick && data is Map<String, dynamic>) {
      final posMs = data['pos'] as int? ?? 0;
      final lyricIdx = data['lyricIdx'] as int? ?? -1;

      _lastPositionSyncMs = posMs;
      _lastPositionSyncTime = DateTime.now();

      _state = _state.copyWith(
        position: Duration(milliseconds: posMs),
        currentLyricIndex: lyricIdx,
      );
      notifyListeners();
    } else if (event == 'volume' && data is Map<String, dynamic>) {
      final vol = (data['volume'] as num?)?.toDouble() ?? _state.volume;
      _state = _state.copyWith(volume: vol);
      notifyListeners();
    }
  }

  void _syncBackgroundNotification() {
    RemoteNotificationService.instance.updateNotification(
      state: _state,
      isConnected: isConnected,
    );
  }

  void sendCommand(String command, [Map<String, dynamic>? data]) {
    if (!isConnected || _channel == null) return;
    try {
      final payload = RemoteProtocol.encodeCommand(command, data);
      _channel!.sink.add(payload);
    } catch (_) {}
  }

  void togglePlay() {
    final nextPlaying = !_state.isPlaying;
    _state = _state.copyWith(isPlaying: nextPlaying);
    _lastPositionSyncTime = DateTime.now();
    notifyListeners();
    _syncBackgroundNotification();
    sendCommand(RemoteProtocol.cmdTogglePlay);
  }

  void play() {
    _state = _state.copyWith(isPlaying: true);
    _lastPositionSyncTime = DateTime.now();
    notifyListeners();
    _syncBackgroundNotification();
    sendCommand(RemoteProtocol.cmdPlay);
  }

  void pause() {
    _state = _state.copyWith(isPlaying: false);
    notifyListeners();
    _syncBackgroundNotification();
    sendCommand(RemoteProtocol.cmdPause);
  }

  void next() => sendCommand(RemoteProtocol.cmdNext);
  void previous() => sendCommand(RemoteProtocol.cmdPrevious);

  void seek(Duration pos) {
    _lastPositionSyncMs = pos.inMilliseconds;
    _lastPositionSyncTime = DateTime.now();
    _state = _state.copyWith(position: pos);
    notifyListeners();
    sendCommand(RemoteProtocol.cmdSeek, {'positionMs': pos.inMilliseconds});
  }

  /// Sets volume with local instantaneous feedback and throttled network transmission
  void setVolume(double vol) {
    final clamped = vol.clamp(0.0, 1.0);
    _state = _state.copyWith(volume: clamped);
    notifyListeners();

    _pendingVolume = clamped;
    if (_volumeThrottleTimer?.isActive ?? false) return;

    _volumeThrottleTimer = Timer(const Duration(milliseconds: 50), () {
      if (_pendingVolume != null) {
        sendCommand(RemoteProtocol.cmdSetVolume, {'volume': _pendingVolume!});
        _pendingVolume = null;
      }
    });
  }

  void toggleShuffle() => sendCommand(RemoteProtocol.cmdToggleShuffle);
  void toggleRepeat() => sendCommand(RemoteProtocol.cmdToggleRepeat);
  void jumpToIndex(int index) => sendCommand(RemoteProtocol.cmdJumpToIndex, {'index': index});
  void seekLyric(int lineIndex) => sendCommand(RemoteProtocol.cmdSeekLyric, {'lineIdx': lineIndex});

  void setSleepTimer(int minutes) {
    _sleepTimerMinutes = minutes;
    sendCommand(RemoteProtocol.cmdSleepTimer, {'minutes': minutes});
    notifyListeners();
  }

  Future<void> disconnect() async {
    _connectionAttemptId++;
    await _forceCleanup();
    await _safeSetWakelock(false);
    await RemoteNotificationService.instance.cancelNotification();
    _status = ConnectionStatus.disconnected;
    _errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _volumeThrottleTimer?.cancel();
    _stopSmoothTicker();
    _forceCleanup();
    _safeSetWakelock(false);
    RemoteNotificationService.instance.cancelNotification();
    super.dispose();
  }
}
