import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../core/models/playback_state.dart';
import '../core/models/remote_protocol.dart';

enum ConnectionStatus { disconnected, connecting, connected, error }

class RemoteClientService extends ChangeNotifier {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;

  ConnectionStatus _status = ConnectionStatus.disconnected;
  String _host = '';
  int _port = 8080;
  String? _errorMessage;

  PlaybackStateSnapshot _state = const PlaybackStateSnapshot();

  // Local sleep timer state for display on remote
  int _sleepTimerMinutes = 0;

  ConnectionStatus get status => _status;
  bool get isConnected => _status == ConnectionStatus.connected;
  String get host => _host;
  int get port => _port;
  String? get errorMessage => _errorMessage;
  PlaybackStateSnapshot get state => _state;
  int get sleepTimerMinutes => _sleepTimerMinutes;

  Future<void> connect(String ipOrHost, {int port = 8080}) async {
    await disconnect();

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
      _channel = WebSocketChannel.connect(uri);

      // Wait for the connection to establish or fail
      await _channel!.ready;

      _status = ConnectionStatus.connected;
      notifyListeners();

      _subscription = _channel!.stream.listen(
        _handleIncomingMessage,
        onDone: () {
          _status = ConnectionStatus.disconnected;
          notifyListeners();
        },
        onError: (e) {
          _status = ConnectionStatus.error;
          _errorMessage = e.toString();
          notifyListeners();
        },
        cancelOnError: true,
      );

      // Request fresh state immediately
      sendCommand(RemoteProtocol.cmdRequestSync);
    } catch (e) {
      _status = ConnectionStatus.error;
      _errorMessage = 'Failed to connect to $_host:$_port: $e';
      notifyListeners();
    }
  }

  void _handleIncomingMessage(dynamic raw) {
    if (raw is! String) return;
    final message = RemoteProtocol.decodeMessage(raw);
    if (message == null || message['type'] != 'event') return;

    final event = message['event'] as String? ?? '';
    final data = message['data'];

    if (event == RemoteProtocol.evtFullState && data is Map<String, dynamic>) {
      _state = PlaybackStateSnapshot.fromJson(data);
      notifyListeners();
    } else if (event == RemoteProtocol.evtPositionTick && data is Map<String, dynamic>) {
      final posMs = data['pos'] as int? ?? 0;
      final lyricIdx = data['lyricIdx'] as int? ?? -1;

      _state = _state.copyWith(
        position: Duration(milliseconds: posMs),
        currentLyricIndex: lyricIdx,
      );
      notifyListeners();
    }
  }

  void sendCommand(String command, [Map<String, dynamic>? data]) {
    if (!isConnected || _channel == null) return;
    try {
      final payload = RemoteProtocol.encodeCommand(command, data);
      _channel!.sink.add(payload);
    } catch (_) {}
  }

  void togglePlay() => sendCommand(RemoteProtocol.cmdTogglePlay);
  void play() => sendCommand(RemoteProtocol.cmdPlay);
  void pause() => sendCommand(RemoteProtocol.cmdPause);
  void next() => sendCommand(RemoteProtocol.cmdNext);
  void previous() => sendCommand(RemoteProtocol.cmdPrevious);
  void seek(Duration pos) => sendCommand(RemoteProtocol.cmdSeek, {'positionMs': pos.inMilliseconds});
  void setVolume(double vol) => sendCommand(RemoteProtocol.cmdSetVolume, {'volume': vol});
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
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
    _status = ConnectionStatus.disconnected;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
    super.dispose();
  }
}
