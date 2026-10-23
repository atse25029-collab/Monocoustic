import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:monocoustic/client/remote_client_service.dart';
import 'package:monocoustic/main.dart';
import 'package:monocoustic/player/audio_player_service.dart';

void main() {
  testWidgets('Monocoustic desktop & remote smoke test', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final audioPlayerService = AudioPlayerService();
    final remoteClientService = RemoteClientService();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: audioPlayerService),
          ChangeNotifierProvider.value(value: remoteClientService),
        ],
        child: const MonocousticApp(),
      ),
    );

    expect(find.byType(MonocousticApp), findsOneWidget);

    audioPlayerService.dispose();
    remoteClientService.dispose();
  });
}
