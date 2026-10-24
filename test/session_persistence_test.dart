import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:monocoustic/player/audio_player_service.dart';
import 'package:monocoustic/core/models/playback_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('xyz.luan/audioplayers.global'), (call) async {
      return 1;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('xyz.luan/audioplayers'), (call) async {
      return 1;
    });
  });

  group('Session Persistence & Settings Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('AudioPlayerService persists and restores session state accurately', () async {
      final service = AudioPlayerService();

      // Configure settings
      await service.setVolume(0.72);
      await service.toggleShuffle(); // true
      await service.toggleRepeat(); // all

      // Verify SharedPreferences received the settings
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('last_volume'), 0.72);
      expect(prefs.getBool('last_is_shuffle'), true);
      expect(prefs.getString('last_repeat_mode'), PlaybackRepeatMode.all.name);

      // Save a simulated song position
      await prefs.setInt('last_playback_position_ms', 145000); // 2:25
      await prefs.setString('last_played_song_path', 'C:\\Music\\test_track.mp3');

      // Create new service instance simulating next launch
      final nextService = AudioPlayerService();
      await nextService.restoreSavedSession();

      expect(nextService.volume, closeTo(0.72, 0.01));
      expect(nextService.isShuffle, true);
      expect(nextService.repeatMode, PlaybackRepeatMode.all);

      service.dispose();
      nextService.dispose();
    });
  });
}
