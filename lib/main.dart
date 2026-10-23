import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'client/remote_client_service.dart';
import 'player/audio_player_service.dart';
import 'ui/desktop/desktop_player_screen.dart';
import 'ui/remote/remote_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final isDesktop = !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  if (isDesktop) {
    await windowManager.ensureInitialized();
    const windowOptions = WindowOptions(
      size: Size(1280, 800),
      minimumSize: Size(960, 600),
      center: true,
      title: 'Monocoustic',
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  final audioPlayerService = AudioPlayerService();
  final remoteClientService = RemoteClientService();

  // If running on desktop, automatically start the local remote-control server & restore music library
  if (isDesktop) {
    await audioPlayerService.startServer(port: 8080);
    audioPlayerService.restoreSavedLibrary();
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: audioPlayerService),
        ChangeNotifierProvider.value(value: remoteClientService),
      ],
      child: const MonocousticApp(),
    ),
  );
}

class MonocousticApp extends StatefulWidget {
  const MonocousticApp({super.key});

  @override
  State<MonocousticApp> createState() => _MonocousticAppState();
}

class _MonocousticAppState extends State<MonocousticApp> {
  // Allow manual mode switching for testing or dual usage
  bool? _forceRemoteMode;

  @override
  Widget build(BuildContext context) {
    final isDesktopPlatform = !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);
    final showRemoteScreen = _forceRemoteMode ?? !isDesktopPlatform;

    return MaterialApp(
      title: 'Monocoustic',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF101217),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF7C4DFF),
          secondary: Color(0xFF00E5FF),
          surface: Color(0xFF161820),
        ),
        sliderTheme: const SliderThemeData(
          activeTrackColor: Color(0xFF7C4DFF),
          inactiveTrackColor: Colors.white12,
          thumbColor: Color(0xFF9E77FF),
        ),
      ),
      home: Scaffold(
        body: Stack(
          children: [
            showRemoteScreen ? const RemoteScreen() : const DesktopPlayerScreen(),

            // Convenient mode switcher badge in the corner for testing / development
            Positioned(
              top: 12,
              right: 12,
              child: Opacity(
                opacity: 0.75,
                child: Material(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () {
                      setState(() {
                        _forceRemoteMode = !showRemoteScreen;
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            showRemoteScreen ? Icons.desktop_windows : Icons.phone_android,
                            size: 14,
                            color: Colors.white70,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            showRemoteScreen ? 'Switch to Desktop' : 'Switch to Remote',
                            style: const TextStyle(fontSize: 11, color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
