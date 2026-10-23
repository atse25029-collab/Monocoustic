import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
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

class _DesktopPlayerScreenState extends State<DesktopPlayerScreen> {
  int _selectedTab = 0; // 0: Library, 1: Lyrics, 2: Remote Pairing
  List<String> _localIps = [];

  @override
  void initState() {
    super.initState();
    _initLocalIps();
  }

  Future<void> _initLocalIps() async {
    final ips = await LocalMusicServer.getLocalIpAddresses();
    if (mounted) {
      setState(() {
        _localIps = ips;
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
    final primaryIp = _localIps.isNotEmpty ? _localIps.first : '127.0.0.1';
    final serverUrl = 'http://$primaryIp:${player.server.port}';

    return Scaffold(
      backgroundColor: const Color(0xFF121318),
      body: Row(
        children: [
          // Left Sidebar Navigation
          _buildSidebar(player, primaryIp),

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
            // App Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.graphic_eq, color: Colors.white, size: 24),
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
            ElevatedButton.icon(
              onPressed: () => _pickAudioFiles(player),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Songs'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(42),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
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
            ElevatedButton.icon(
              onPressed: () => _pickAudioFiles(player),
              icon: const Icon(Icons.folder_open),
              label: const Text('Browse Files'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
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
            leading: IconButton(
              icon: Icon(
                isPlayingThis && player.isPlaying
                    ? Icons.pause_circle_filled
                    : Icons.play_circle_filled,
                color: isPlayingThis ? Theme.of(context).colorScheme.primary : Colors.white70,
                size: 32,
              ),
              onPressed: () {
                if (isPlayingThis) {
                  player.togglePlay();
                } else {
                  player.playAtIndex(index);
                }
              },
            ),
            title: Text(
              item.title,
              style: TextStyle(
                fontWeight: isPlayingThis ? FontWeight.bold : FontWeight.normal,
                color: isPlayingThis ? Colors.white : Colors.white.withValues(alpha: 0.9),
              ),
            ),
            subtitle: Text(
              item.artist,
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
                const SizedBox(width: 12),
                IconButton(
                  icon: const Icon(Icons.close, size: 18, color: Colors.white30),
                  onPressed: () => player.removeSong(index),
                ),
              ],
            ),
          ),
        );
      },
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
          Text(
            currentSong.title,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 4),
          Text(
            currentSong.artist,
            style: const TextStyle(fontSize: 14, color: Colors.white54),
          ),
          const SizedBox(height: 8),
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
          constraints: const BoxConstraints(maxWidth: 620),
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
                'Connect your Android phone to the same Wi-Fi network to control music, skip songs, adjust volume, and view real-time lyrics remotely.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.white54, height: 1.4),
              ),
              const SizedBox(height: 28),

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
              const SizedBox(height: 24),

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
              const SizedBox(height: 24),

              // Step-by-step instructions
              const Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('How to Connect:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white70)),
                    SizedBox(height: 8),
                    Text('1. Install the Monocoustic Android APK on your phone.', style: TextStyle(color: Colors.white54, fontSize: 13)),
                    SizedBox(height: 4),
                    Text('2. Make sure your phone and laptop are on the same Wi-Fi.', style: TextStyle(color: Colors.white54, fontSize: 13)),
                    SizedBox(height: 4),
                    Text('3. Enter the IP shown above into the mobile app and tap "Connect"!', style: TextStyle(color: Colors.white54, fontSize: 13)),
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
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        color: Color(0xFF16181F),
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        children: [
          // Current Track info
          SizedBox(
            width: 200,
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.music_note, color: Colors.white54, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        song?.title ?? 'No Track Playing',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white, fontSize: 13),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        song?.artist ?? 'Select from library',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: Colors.white54),
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
                      icon: Icon(
                        Icons.shuffle,
                        size: 18,
                        color: player.isShuffle ? Theme.of(context).colorScheme.primary : Colors.white38,
                      ),
                      onPressed: player.toggleShuffle,
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_previous, color: Colors.white, size: 22),
                      onPressed: player.previous,
                    ),
                    const SizedBox(width: 4),
                    Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: Icon(
                          player.isPlaying ? Icons.pause : Icons.play_arrow,
                          color: Colors.white,
                          size: 24,
                        ),
                        onPressed: player.togglePlay,
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.skip_next, color: Colors.white, size: 22),
                      onPressed: player.next,
                    ),
                    IconButton(
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

                // Seek bar
                Row(
                  children: [
                    Text(_formatDuration(player.position), style: const TextStyle(fontSize: 10, color: Colors.white38)),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 2,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
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
                    Text(_formatDuration(player.duration), style: const TextStyle(fontSize: 10, color: Colors.white38)),
                  ],
                ),
              ],
            ),
          ),

          // Volume & Quick Actions
          SizedBox(
            width: 195,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: 'Lyrics View',
                  icon: Icon(
                    Icons.subtitles,
                    size: 20,
                    color: _selectedTab == 1 ? Theme.of(context).colorScheme.primary : Colors.white60,
                  ),
                  onPressed: () => setState(() => _selectedTab = 1),
                ),
                IconButton(
                  tooltip: 'Remote Control QR',
                  icon: Icon(
                    Icons.qr_code,
                    size: 20,
                    color: _selectedTab == 2 ? Theme.of(context).colorScheme.primary : Colors.white60,
                  ),
                  onPressed: () => setState(() => _selectedTab = 2),
                ),
                Icon(
                  player.volume == 0 ? Icons.volume_off : Icons.volume_up,
                  size: 18,
                  color: Colors.white54,
                ),
                SizedBox(
                  width: 55,
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                    ),
                    child: Slider(
                      value: player.volume,
                      max: 1.0,
                      onChanged: (val) => player.setVolume(val),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
