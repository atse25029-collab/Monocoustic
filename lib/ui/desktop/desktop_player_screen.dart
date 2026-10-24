import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:window_manager/window_manager.dart';
import '../../core/models/playback_state.dart';
import '../../core/models/song.dart';
import '../../player/audio_player_service.dart';
import '../../server/local_music_server.dart';
import '../widgets/lyrics_view.dart';

class DesktopPlayerScreen extends StatefulWidget {
  const DesktopPlayerScreen({super.key});

  @override
  State<DesktopPlayerScreen> createState() => _DesktopPlayerScreenState();
}

class _DesktopPlayerScreenState extends State<DesktopPlayerScreen> with WindowListener {
  int _selectedTab = 0; // 0: Library, 1: Lyrics, 2: Remote Pairing
  List<NetworkAddressInfo> _networkInterfaces = [];
  int _selectedInterfaceIndex = 0;
  bool _isFullScreen = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    HardwareKeyboard.instance.addHandler(_handleGlobalKeyEvent);
    _initLocalIps();
    _checkInitialFullScreen();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleGlobalKeyEvent);
    windowManager.removeListener(this);
    super.dispose();
  }

  bool _handleGlobalKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.f11) {
        _toggleFullScreen();
        return true;
      } else if (event.logicalKey == LogicalKeyboardKey.escape && _isFullScreen) {
        _toggleFullScreen();
        return true;
      }
    }
    return false;
  }

  @override
  void onWindowEnterFullScreen() {
    if (mounted) setState(() => _isFullScreen = true);
  }

  @override
  void onWindowLeaveFullScreen() {
    if (mounted) setState(() => _isFullScreen = false);
  }

  Future<void> _checkInitialFullScreen() async {
    try {
      final fs = await windowManager.isFullScreen();
      if (mounted) setState(() => _isFullScreen = fs);
    } catch (_) {}
  }

  Future<void> _toggleFullScreen() async {
    try {
      final isFs = await windowManager.isFullScreen();
      await windowManager.setFullScreen(!isFs);
      final newFs = await windowManager.isFullScreen();
      if (mounted) {
        setState(() {
          _isFullScreen = newFs;
        });
      }
    } catch (_) {}
  }

  Future<void> _initLocalIps() async {
    final ifaces = await LocalMusicServer.getDetailedNetworkInterfaces();
    if (mounted) {
      setState(() {
        _networkInterfaces = ifaces;
        _selectedInterfaceIndex = 0;
      });
    }
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _pickAudioFiles(AudioPlayerService player) async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'flac', 'wav', 'aac', 'ogg', 'm4a'],
      dialogTitle: 'Select Music Tracks',
    );

    if (files.isNotEmpty) {
      final paths = files
          .where((f) => f.path != null)
          .map((f) => f.path!)
          .toList();
      if (paths.isNotEmpty) {
        await player.addFiles(paths);
      }
    }
  }

  Future<void> _pickFolder(AudioPlayerService player) async {
    final folderPath = await FilePicker.getDirectoryPath(
      dialogTitle: 'Select Music Folder',
    );
    if (folderPath != null && folderPath.isNotEmpty) {
      await player.addFolder(folderPath);
    }
  }

  Future<void> _pickLyricFile(AudioPlayerService player, int songIndex) async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['lrc', 'smi', 'sami'],
      dialogTitle: 'Select Lyric File (.lrc or .smi)',
    );

    if (files.isNotEmpty && files.first.path != null) {
      await player.setCustomLyrics(songIndex, files.first.path!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<AudioPlayerService>();
    final song = player.currentSong;

    final activeIp = (_networkInterfaces.isNotEmpty &&
            _selectedInterfaceIndex < _networkInterfaces.length)
        ? _networkInterfaces[_selectedInterfaceIndex].ip
        : '127.0.0.1';
    final serverUrl = 'http://$activeIp:${player.server.port}';

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.f11): _toggleFullScreen,
        const SingleActivator(LogicalKeyboardKey.escape): () async {
          if (_isFullScreen) {
            await _toggleFullScreen();
          }
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: const Color(0xFF121318),
          body: Stack(
            children: [
              Row(
                children: [
                  // Left Sidebar Navigation (hidden in lyrics view when fullscreen for maximum immersion, or accessible)
                  if (!_isFullScreen || _selectedTab != 1)
                    _buildSidebar(player, activeIp),

                  // Main Center Area
                  Expanded(
                    child: Column(
                      children: [
                        Expanded(
                          child: IndexedStack(
                            index: _selectedTab,
                            children: [
                              _buildLibraryView(player),
                              _buildLyricsView(player),
                              _buildRemotePairingView(player, serverUrl),
                            ],
                          ),
                        ),

                        // Bottom Persistent Player Bar
                        _buildPlayerBar(player, song),
                      ],
                    ),
                  ),
                ],
              ),

              // Floating Exit Fullscreen Button in top right when in Fullscreen
              if (_isFullScreen)
                Positioned(
                  top: 16,
                  right: 16,
                  child: Material(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(20),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: _toggleFullScreen,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.fullscreen_exit, size: 18, color: Colors.white),
                            SizedBox(width: 6),
                            Text(
                              'Exit Full Screen (Esc / F11)',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSidebar(AudioPlayerService player, String primaryIp) {
    return Material(
      color: const Color(0xFF181A20),
      child: Container(
        width: 250,
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // App Header with custom logo
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.asset(
                    'assets/logo.png',
                    width: 36,
                    height: 36,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.graphic_eq, color: Colors.white, size: 20),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Monocoustic',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),

            // Nav Items
            _buildNavItem(0, Icons.queue_music, 'Queue & Library'),
            _buildNavItem(1, Icons.subtitles_outlined, 'Lyrics Canvas'),
            _buildNavItem(2, Icons.phone_android, 'Remote Pairing'),

            const Divider(color: Colors.white12, height: 32),

            // Quick Actions
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _pickAudioFiles(player),
                    icon: const Icon(Icons.music_note, size: 16),
                    label: const Text('Add Files', style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickFolder(player),
                    icon: const Icon(Icons.folder_open, size: 16),
                    label: const Text('Add Folder', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white24),
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),

            const Spacer(),

            // Server Connection Badge
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Colors.greenAccent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Remote Server Active',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white70),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$primaryIp:${player.server.port}',
                    style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.white54),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${player.server.connectedClientsCount} remote phone(s) connected',
                    style: const TextStyle(fontSize: 11, color: Colors.white38),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _selectedTab == index;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        selected: isSelected,
        selectedTileColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        leading: Icon(
          icon,
          color: isSelected ? Theme.of(context).colorScheme.primary : Colors.white60,
        ),
        title: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            color: isSelected ? Colors.white : Colors.white70,
          ),
        ),
        onTap: () => setState(() => _selectedTab = index),
      ),
    );
  }

  Widget _buildLibraryView(AudioPlayerService player) {
    if (player.queue.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.music_note_rounded, size: 80, color: Colors.white24),
            const SizedBox(height: 16),
            const Text(
              'Your Library is Empty',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white70),
            ),
            const SizedBox(height: 8),
            const Text(
              'Add audio files (.mp3, .flac, .wav, .ogg). Companion .smi/.lrc files are loaded automatically.',
              style: TextStyle(fontSize: 13, color: Colors.white38),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: () => _pickAudioFiles(player),
                  icon: const Icon(Icons.music_note),
                  label: const Text('Browse Files'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(width: 16),
                OutlinedButton.icon(
                  onPressed: () => _pickFolder(player),
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Open Folder Library'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white38),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Library Header Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: const BoxDecoration(
            color: Color(0xFF161820),
            border: Border(bottom: BorderSide(color: Colors.white10)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Queue & Library (${player.queue.length} tracks)',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                    ),
                    if (player.savedFolderPath != null)
                      Text(
                        'Saved Folder: ${player.savedFolderPath}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: Colors.white38),
                      ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => _pickAudioFiles(player),
                icon: const Icon(Icons.music_note, size: 14),
                label: const Text('Add Files', style: TextStyle(fontSize: 11)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: const BorderSide(color: Colors.white24),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => _pickFolder(player),
                icon: const Icon(Icons.folder_open, size: 14),
                label: const Text('Change Folder', style: TextStyle(fontSize: 11)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: const BorderSide(color: Colors.white24),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Clear Library Queue',
                icon: const Icon(Icons.delete_sweep_outlined, size: 20, color: Colors.white38),
                onPressed: player.clearQueue,
              ),
            ],
          ),
        ),

        // Tracks List
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(24),
            itemCount: player.queue.length,
            itemBuilder: (context, index) {
        final item = player.queue[index];
        final isPlayingThis = (index == player.currentIndex);

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          color: isPlayingThis
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.15)
              : const Color(0xFF1B1D24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: isPlayingThis
                ? BorderSide(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5))
                : BorderSide.none,
          ),
          child: ListTile(
            leading: SizedBox(
              width: 44,
              height: 44,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: item.albumArtPath != null
                        ? Image.file(
                            File(item.albumArtPath!),
                            width: 44,
                            height: 44,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Container(
                              width: 44,
                              height: 44,
                              color: Colors.white10,
                              child: const Icon(Icons.music_note, color: Colors.white38, size: 20),
                            ),
                          )
                        : Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: Colors.white10,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.music_note, color: Colors.white38, size: 20),
                          ),
                  ),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () {
                        if (isPlayingThis) {
                          player.togglePlay();
                        } else {
                          player.playAtIndex(index);
                        }
                      },
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: isPlayingThis
                              ? Colors.black.withValues(alpha: 0.4)
                              : Colors.black.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          isPlayingThis && player.isPlaying
                              ? Icons.pause_circle_filled
                              : Icons.play_circle_filled,
                          color: isPlayingThis ? Theme.of(context).colorScheme.primary : Colors.white,
                          size: 28,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            title: Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: isPlayingThis ? FontWeight.bold : FontWeight.normal,
                color: isPlayingThis ? Colors.white : Colors.white.withValues(alpha: 0.9),
              ),
            ),
            subtitle: Text(
              item.album.isNotEmpty ? '${item.artist} • ${item.album}' : item.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.5)),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Lyric status badge
                if (item.lyrics.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.greenAccent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.check_circle, size: 12, color: Colors.greenAccent),
                        const SizedBox(width: 4),
                        Text(
                          item.lyricPath?.endsWith('.smi') == true ? 'SMI' : 'LRC',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.greenAccent,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  TextButton.icon(
                    onPressed: () => _pickLyricFile(player, index),
                    icon: const Icon(Icons.add_link, size: 14),
                    label: const Text('Add Lyric', style: TextStyle(fontSize: 11)),
                    style: TextButton.styleFrom(foregroundColor: Colors.white54),
                  ),
              ],
            ),
          ),
        );
      },
    ),
  ),
],
);
}

  Widget _buildLyricsView(AudioPlayerService player) {
    final currentSong = player.currentSong;
    if (currentSong == null) {
      return const Center(
        child: Text('Play a song to view synchronized lyrics', style: TextStyle(color: Colors.white38)),
      );
    }

    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.topCenter,
          radius: 1.2,
          colors: [
            Color(0xFF1E2230),
            Color(0xFF121318),
          ],
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 24),
          if (currentSong.albumArtPath != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.file(
                File(currentSong.albumArtPath!),
                width: 140,
                height: 140,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
            const SizedBox(height: 16),
          ],
          Text(
            currentSong.title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 4),
          Text(
            currentSong.album.isNotEmpty
                ? '${currentSong.artist} • ${currentSong.album}'
                : currentSong.artist,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: Colors.white54),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: LyricsView(
              lyrics: currentSong.lyrics,
              activeIndex: player.currentLyricIndex,
              onLineTap: (idx) => player.seekToLyricLine(idx),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRemotePairingView(AudioPlayerService player, String serverUrl) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(40),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 640),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1D24),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_tethering, size: 48, color: Colors.lightBlueAccent),
              const SizedBox(height: 16),
              const Text(
                'Control From Your Bed or Couch',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 8),
              const Text(
                'Connect your Android phone to control playback, volume, and view real-time lyrics from your bed.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.white54, height: 1.4),
              ),
              const SizedBox(height: 20),

              // Network Interface Selector Chips
              if (_networkInterfaces.length > 1) ...[
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Select Network Connection:',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white70),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: List.generate(_networkInterfaces.length, (idx) {
                    final iface = _networkInterfaces[idx];
                    final isSelected = _selectedInterfaceIndex == idx;
                    final isWifi = iface.interfaceName.toLowerCase().contains(RegExp(r'wi-fi|wlan'));

                    return ChoiceChip(
                      selected: isSelected,
                      selectedColor: Theme.of(context).colorScheme.primary,
                      backgroundColor: Colors.white.withValues(alpha: 0.05),
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isWifi
                                ? Icons.wifi
                                : (iface.isVirtual ? Icons.computer : Icons.lan),
                            size: 14,
                            color: isSelected ? Colors.white : Colors.white60,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${iface.interfaceName} (${iface.ip})',
                            style: TextStyle(
                              fontSize: 12,
                              color: isSelected ? Colors.white : Colors.white70,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          if (isWifi && !iface.isVirtual) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.greenAccent.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Hotspot/Wi-Fi',
                                style: TextStyle(fontSize: 9, color: Colors.greenAccent, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ],
                      ),
                      onSelected: (selected) {
                        if (selected) {
                          setState(() {
                            _selectedInterfaceIndex = idx;
                          });
                        }
                      },
                    );
                  }),
                ),
                const SizedBox(height: 20),
              ],

              // QR Code Container
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: QrImageView(
                  data: serverUrl,
                  version: QrVersions.auto,
                  size: 200.0,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 20),

              // Server URL Box
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.link, size: 18, color: Colors.lightBlueAccent),
                    const SizedBox(width: 8),
                    SelectableText(
                      serverUrl,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Step-by-step instructions
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white10),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('How to Connect with Phone Hotspot:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white70)),
                    SizedBox(height: 8),
                    Text('1. Connect your laptop to your phone\'s hotspot.', style: TextStyle(color: Colors.white54, fontSize: 13)),
                    SizedBox(height: 4),
                    Text('2. Make sure the Wi-Fi option is selected above (e.g. 10.83.223.201).', style: TextStyle(color: Colors.white54, fontSize: 13)),
                    SizedBox(height: 4),
                    Text('3. On your phone app, enter that exact IP and tap "Connect to Laptop"!', style: TextStyle(color: Colors.white54, fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlayerBar(AudioPlayerService player, Song? song) {
    return Container(
      height: 90,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: const BoxDecoration(
        color: Color(0xFF16181F),
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        children: [
          // Current Track info & Timeframe badge
          SizedBox(
            width: 210,
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: song?.albumArtPath != null
                      ? Image.file(
                          File(song!.albumArtPath!),
                          width: 44,
                          height: 44,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            width: 44,
                            height: 44,
                            color: Colors.white10,
                            child: const Icon(Icons.music_note, color: Colors.white54, size: 22),
                          ),
                        )
                      : Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.white10,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.music_note, color: Colors.white54, size: 22),
                        ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        song?.title ?? 'No Track Playing',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 12),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        song != null
                            ? (song.album.isNotEmpty ? '${song.artist} • ${song.album}' : song.artist)
                            : 'Select from library',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10, color: Colors.white54),
                      ),
                      const SizedBox(height: 2),
                      // Prominent Timeframe badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          '${_formatDuration(player.position)} / ${_formatDuration(player.duration)}',
                          style: TextStyle(
                            fontSize: 9,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Central Playback Controls & Scrubber
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: player.isShuffle ? 'Shuffle: On' : 'Shuffle: Off',
                      icon: Icon(
                        Icons.shuffle,
                        size: 18,
                        color: player.isShuffle ? Theme.of(context).colorScheme.primary : Colors.white38,
                      ),
                      onPressed: player.toggleShuffle,
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.skip_previous, color: Colors.white, size: 22),
                      onPressed: player.previous,
                    ),
                    const SizedBox(width: 4),
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        icon: Icon(
                          player.isPlaying ? Icons.pause : Icons.play_arrow,
                          color: Colors.white,
                          size: 22,
                        ),
                        onPressed: player.togglePlay,
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.skip_next, color: Colors.white, size: 22),
                      onPressed: player.next,
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: player.repeatMode == PlaybackRepeatMode.off
                          ? 'Repeat: Off'
                          : (player.repeatMode == PlaybackRepeatMode.all
                              ? 'Repeat: All'
                              : 'Repeat: Single Track'),
                      icon: Icon(
                        player.repeatMode == PlaybackRepeatMode.one
                            ? Icons.repeat_one
                            : Icons.repeat,
                        size: 18,
                        color: player.repeatMode != PlaybackRepeatMode.off
                            ? Theme.of(context).colorScheme.primary
                            : Colors.white38,
                      ),
                      onPressed: player.toggleRepeat,
                    ),
                  ],
                ),

                // Seek bar with prominent start and end times
                Row(
                  children: [
                    SizedBox(
                      width: 40,
                      child: Text(
                        _formatDuration(player.position),
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w600,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: SizedBox(
                        height: 22,
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 3,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                            overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                            activeTrackColor: Theme.of(context).colorScheme.primary,
                            inactiveTrackColor: Colors.white12,
                            thumbColor: Colors.white,
                          ),
                          child: Slider(
                            value: player.position.inMilliseconds
                                .clamp(0, player.duration.inMilliseconds.clamp(1, 999999999))
                                .toDouble(),
                            max: player.duration.inMilliseconds > 0
                                ? player.duration.inMilliseconds.toDouble()
                                : 1.0,
                            onChanged: (val) {
                              player.seek(Duration(milliseconds: val.toInt()));
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 40,
                      child: Text(
                        _formatDuration(player.duration),
                        textAlign: TextAlign.left,
                        style: const TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w600,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Volume & Quick Actions
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(),
                tooltip: _isFullScreen ? 'Exit Full Screen (F11 / Esc)' : 'Full Screen (F11)',
                icon: Icon(
                  _isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
                  size: 20,
                  color: _isFullScreen ? Theme.of(context).colorScheme.primary : Colors.white60,
                ),
                onPressed: _toggleFullScreen,
              ),
              const SizedBox(width: 4),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(),
                tooltip: 'Lyrics Canvas',
                icon: Icon(
                  Icons.subtitles,
                  size: 19,
                  color: _selectedTab == 1 ? Theme.of(context).colorScheme.primary : Colors.white60,
                ),
                onPressed: () => setState(() => _selectedTab = 1),
              ),
              const SizedBox(width: 4),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(),
                tooltip: 'Remote Control QR',
                icon: Icon(
                  Icons.qr_code,
                  size: 19,
                  color: _selectedTab == 2 ? Theme.of(context).colorScheme.primary : Colors.white60,
                ),
                onPressed: () => setState(() => _selectedTab = 2),
              ),
              const SizedBox(width: 6),
              // Laptop Master Volume Slider & Mute Toggle
              Tooltip(
                message: 'Laptop Master Volume: ${(player.volume * 100).round()}%',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.all(4),
                      constraints: const BoxConstraints(),
                      icon: Icon(
                        player.volume == 0 ? Icons.volume_off : Icons.volume_up,
                        size: 18,
                        color: Colors.white70,
                      ),
                      onPressed: () {
                        if (player.volume > 0) {
                          player.setVolume(0);
                        } else {
                          player.setVolume(0.5);
                        }
                      },
                    ),
                    SizedBox(
                      width: 60,
                      height: 22,
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 2,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 8),
                          activeTrackColor: Theme.of(context).colorScheme.primary,
                          inactiveTrackColor: Colors.white12,
                          thumbColor: Colors.white,
                        ),
                        child: Slider(
                          value: player.volume,
                          max: 1.0,
                          onChanged: (val) => player.setVolume(val),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 30,
                      child: Text(
                        '${(player.volume * 100).round()}%',
                        style: const TextStyle(fontSize: 10, color: Colors.white54, fontFamily: 'monospace'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
