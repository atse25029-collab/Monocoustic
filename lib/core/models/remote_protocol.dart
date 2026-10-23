import 'dart:convert';

class RemoteProtocol {
  // Command names from Client -> Server
  static const String cmdPlay = 'play';
  static const String cmdPause = 'pause';
  static const String cmdTogglePlay = 'toggle_play';
  static const String cmdNext = 'next';
  static const String cmdPrevious = 'previous';
  static const String cmdSeek = 'seek';
  static const String cmdSetVolume = 'set_volume';
  static const String cmdToggleShuffle = 'toggle_shuffle';
  static const String cmdToggleRepeat = 'toggle_repeat';
  static const String cmdJumpToIndex = 'jump_to_index';
  static const String cmdSeekLyric = 'seek_lyric';
  static const String cmdSleepTimer = 'sleep_timer'; // cancel or set minutes
  static const String cmdRequestSync = 'request_sync';

  // Event names from Server -> Client
  static const String evtFullState = 'full_state';
  static const String evtPositionTick = 'position_tick';
  static const String evtTrackChanged = 'track_changed';
  static const String evtLyricsUpdate = 'lyrics_update';

  static String encodeCommand(String command, [Map<String, dynamic>? data]) {
    return jsonEncode({
      'type': 'command',
      'action': command,
      'data': ?data,
    });
  }

  static String encodeEvent(String event, dynamic data) {
    return jsonEncode({
      'type': 'event',
      'event': event,
      'data': data,
    });
  }

  static Map<String, dynamic>? decodeMessage(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {}
    return null;
  }
}
