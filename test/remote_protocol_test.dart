import 'package:flutter_test/flutter_test.dart';
import 'package:monocoustic/client/remote_client_service.dart';
import 'package:monocoustic/core/models/lyric_line.dart';
import 'package:monocoustic/core/models/playback_state.dart';
import 'package:monocoustic/core/models/remote_protocol.dart';
import 'package:monocoustic/core/models/song.dart';
import 'package:monocoustic/server/local_music_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Remote Protocol and Server-Client Tests', () {
    late LocalMusicServer server;
    late RemoteClientService client;
    int boundPort = 0;
    PlaybackStateSnapshot mockSnapshot = const PlaybackStateSnapshot(
      volume: 0.8,
      isPlaying: false,
    );
    String? lastReceivedCommand;
    Map<String, dynamic>? lastReceivedData;

    setUp(() async {
      server = LocalMusicServer();
      server.getStateSnapshot = () => mockSnapshot;
      server.onCommandReceived = (cmd, data) {
        lastReceivedCommand = cmd;
        lastReceivedData = data;
      };

      boundPort = await server.start(port: 0);
      client = RemoteClientService();
    });

    tearDown(() async {
      await client.disconnect();
      client.dispose();
      await server.stop();
    });

    test('client connects to server and receives full initial state', () async {
      await client.connect('127.0.0.1', port: boundPort);
      expect(client.isConnected, true);

      // Allow server upgrade loop to complete
      await Future.delayed(const Duration(milliseconds: 100));
      expect(server.connectedClientsCount, 1);
      expect(client.state.volume, 0.8);
    });

    test('client receives live position tick from server', () async {
      await client.connect('127.0.0.1', port: boundPort);
      await Future.delayed(const Duration(milliseconds: 100));

      server.broadcastPosition(45200, 3);
      await Future.delayed(const Duration(milliseconds: 150));

      expect(client.state.position.inMilliseconds, 45200);
      expect(client.state.currentLyricIndex, 3);
    });

    test('client sends commands to server correctly', () async {
      await client.connect('127.0.0.1', port: boundPort);
      await Future.delayed(const Duration(milliseconds: 100));

      client.setVolume(0.65);
      await Future.delayed(const Duration(milliseconds: 150));

      expect(lastReceivedCommand, RemoteProtocol.cmdSetVolume);
      expect(lastReceivedData?['volume'], 0.65);

      client.togglePlay();
      await Future.delayed(const Duration(milliseconds: 150));
      expect(lastReceivedCommand, RemoteProtocol.cmdTogglePlay);
    });

    test('handles failed connection attempt and connects successfully on retry', () async {
      // First attempt with closed/wrong port
      await client.connect('127.0.0.1', port: 59999);
      expect(client.isConnected, false);
      expect(client.status, ConnectionStatus.error);

      // Second attempt with valid server port in the same session
      await client.connect('127.0.0.1', port: boundPort);
      expect(client.isConnected, true);
      expect(client.status, ConnectionStatus.connected);
    });

    test('song and lyrics JSON serialization roundtrip', () {
      const song = Song(
        id: 's_1',
        title: 'Bohemian Rhapsody',
        artist: 'Queen',
        album: 'A Night at the Opera',
        duration: Duration(minutes: 5, seconds: 55),
        filePath: 'D:/Music/queen.mp3',
        lyricPath: 'D:/Music/queen.lrc',
        lyrics: [
          LyricLine(timestamp: Duration(seconds: 1), text: 'Is this the real life?'),
          LyricLine(
            timestamp: Duration(seconds: 5),
            text: 'Is this just fantasy?',
            translation: 'Isto e fantasia?',
          ),
        ],
      );

      final json = song.toJson();
      final revived = Song.fromJson(json);

      expect(revived.id, song.id);
      expect(revived.title, song.title);
      expect(revived.lyrics.length, 2);
      expect(revived.lyrics[1].translation, 'Isto e fantasia?');
    });
  });
}
