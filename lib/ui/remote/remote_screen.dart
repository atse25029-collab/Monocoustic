import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../client/remote_client_service.dart';
import '../../core/models/playback_state.dart';
import '../widgets/lyrics_view.dart';

class RemoteScreen extends StatefulWidget {
  const RemoteScreen({super.key});

  @override
  State<RemoteScreen> createState() => _RemoteScreenState();
}

class _RemoteScreenState extends State<RemoteScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _ipController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _ipController.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  void _showSleepTimerModal(BuildContext context, RemoteClientService client) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E2028),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.bedtime, color: Colors.amberAccent, size: 24),
                  const SizedBox(width: 8),
                  const Text(
                    'Bedtime Sleep Timer',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Automatically pauses desktop playback when you fall asleep.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.white54),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [15, 30, 45, 60].map((mins) {
                  final isSelected = client.sleepTimerMinutes == mins;
                  return ChoiceChip(
                    label: Text('$mins mins'),
                    selected: isSelected,
                    selectedColor: Theme.of(context).colorScheme.primary,
                    backgroundColor: Colors.white10,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : Colors.white70,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                    onSelected: (_) {
                      client.setSleepTimer(mins);
                      Navigator.pop(ctx);
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              if (client.sleepTimerMinutes > 0)
                TextButton.icon(
                  onPressed: () {
                    client.setSleepTimer(0);
                    Navigator.pop(ctx);
                  },
                  icon: const Icon(Icons.timer_off, color: Colors.redAccent, size: 18),
                  label: const Text('Cancel Sleep Timer', style: TextStyle(color: Colors.redAccent)),
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final client = context.watch<RemoteClientService>();

    return Scaffold(
      backgroundColor: const Color(0xFF101217),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161820),
        elevation: 0,
        title: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: client.isConnected ? Colors.greenAccent : Colors.redAccent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              client.isConnected ? 'Monocoustic Remote' : 'Connect to Laptop',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          if (client.isConnected) ...[
            IconButton(
              tooltip: 'Sleep Timer',
              icon: Icon(
                Icons.bedtime,
                color: client.sleepTimerMinutes > 0 ? Colors.amberAccent : Colors.white60,
              ),
              onPressed: () => _showSleepTimerModal(context, client),
            ),
            IconButton(
              tooltip: 'Disconnect',
              icon: const Icon(Icons.power_settings_new, color: Colors.white60),
              onPressed: client.disconnect,
            ),
          ],
        ],
        bottom: client.isConnected
            ? TabBar(
                controller: _tabController,
                indicatorColor: Theme.of(context).colorScheme.primary,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white38,
                tabs: const [
                  Tab(icon: Icon(Icons.music_note), text: 'Now Playing & Lyrics'),
                  Tab(icon: Icon(Icons.queue_music), text: 'Desktop Queue'),
                ],
              )
            : null,
      ),
      body: client.isConnected ? _buildConnectedView(client) : _buildPairingView(client),
    );
  }

  Widget _buildPairingView(RemoteClientService client) {
    final isConnecting = client.status == ConnectionStatus.connecting;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1C24),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Custom Unique App Icon
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Image.asset(
                  'assets/logo.png',
                  width: 80,
                  height: 80,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.graphic_eq,
                      size: 48,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Couch & Bed Remote',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 8),
              const Text(
                'Enter the IP displayed on your laptop to control playback and view synchronized lyrics.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.white54, height: 1.4),
              ),
              const SizedBox(height: 20),

              // Hotspot Tip banner
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blueAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.2)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.wifi_tethering, size: 18, color: Colors.lightBlueAccent),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Using Phone Hotspot? Look for your laptop\'s Wi-Fi IP on screen (e.g. 10.83.223.201). Avoid virtual VMware/VPN IPs.',
                        style: TextStyle(fontSize: 11, color: Colors.white70, height: 1.3),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // IP Input
              TextField(
                controller: _ipController,
                style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 16),
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  labelText: 'Laptop IP / Host',
                  hintText: 'e.g. 10.83.223.201 or 192.168.1.15',
                  prefixIcon: const Icon(Icons.wifi, color: Colors.white38),
                  filled: true,
                  fillColor: Colors.black26,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.white12),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              if (client.errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            client.errorMessage!,
                            style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              ElevatedButton.icon(
                onPressed: isConnecting
                    ? null
                    : () {
                        final text = _ipController.text.trim();
                        if (text.isEmpty || text.endsWith('.')) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Please enter your laptop\'s full IP address from the screen (e.g. 10.83.223.201)'),
                              backgroundColor: Colors.redAccent,
                            ),
                          );
                          return;
                        }
                        client.connect(text);
                      },
                icon: isConnecting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.login),
                label: Text(isConnecting ? 'Connecting...' : 'Connect to Laptop'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConnectedView(RemoteClientService client) {
    return TabBarView(
      controller: _tabController,
      children: [
        _buildNowPlayingTab(client),
        _buildQueueTab(client),
      ],
    );
  }

  Widget _buildNowPlayingTab(RemoteClientService client) {
    final state = client.state;
    final song = state.currentSong;

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Column(
                  children: [
                    // Album Art
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.network(
                        'http://${client.host}:${client.port}/album-art',
                        width: 120,
                        height: 120,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            color: const Color(0xFF161822),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: const Icon(Icons.music_note, color: Colors.white24, size: 48),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Song Title & Artist
                    Text(
                      song?.title ?? 'No Track Playing',
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      (song != null && song.album.isNotEmpty)
                          ? '${song.artist} • ${song.album}'
                          : (song?.artist ?? 'Laptop Player'),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: Colors.white54),
                    ),
                    const SizedBox(height: 14),

                    // Live Synchronized Lyrics Area
                    Container(
                      height: constraints.maxHeight * 0.35,
                      decoration: BoxDecoration(
                        color: const Color(0xFF161822),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: LyricsView(
                          lyrics: song?.lyrics ?? [],
                          activeIndex: state.currentLyricIndex,
                          isCompact: true,
                          onLineTap: (idx) => client.seekLyric(idx),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Progress bar & Timestamps
                    Row(
                      children: [
                        Text(_formatDuration(state.position), style: const TextStyle(fontSize: 12, color: Colors.white38)),
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 3,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                            ),
                            child: Slider(
                              value: state.position.inMilliseconds
                                  .clamp(0, state.duration.inMilliseconds.clamp(1, 999999999))
                                  .toDouble(),
                              max: state.duration.inMilliseconds > 0
                                  ? state.duration.inMilliseconds.toDouble()
                                  : 1.0,
                              onChanged: (val) {
                                client.seek(Duration(milliseconds: val.toInt()));
                              },
                            ),
                          ),
                        ),
                        Text(_formatDuration(state.duration), style: const TextStyle(fontSize: 12, color: Colors.white38)),
                      ],
                    ),

                    // Playback Control Buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        IconButton(
                          icon: Icon(
                            Icons.shuffle,
                            color: state.isShuffle ? Theme.of(context).colorScheme.primary : Colors.white38,
                          ),
                          onPressed: client.toggleShuffle,
                        ),
                        IconButton(
                          icon: const Icon(Icons.skip_previous, size: 36, color: Colors.white),
                          onPressed: client.previous,
                        ),
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            icon: Icon(
                              state.isPlaying ? Icons.pause : Icons.play_arrow,
                              color: Colors.white,
                              size: 36,
                            ),
                            onPressed: client.togglePlay,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.skip_next, size: 36, color: Colors.white),
                          onPressed: client.next,
                        ),
                        IconButton(
                          icon: Icon(
                            state.repeatMode == PlaybackRepeatMode.one ? Icons.repeat_one : Icons.repeat,
                            color: state.repeatMode != PlaybackRepeatMode.off ? Theme.of(context).colorScheme.primary : Colors.white38,
                          ),
                          onPressed: client.toggleRepeat,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Volume Slider
                    Row(
                      children: [
                        const Icon(Icons.volume_down, size: 20, color: Colors.white38),
                        Expanded(
                          child: Slider(
                            value: state.volume,
                            max: 1.0,
                            onChanged: (val) => client.setVolume(val),
                          ),
                        ),
                        const Icon(Icons.volume_up, size: 20, color: Colors.white38),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildQueueTab(RemoteClientService client) {
    final queue = client.state.queue;
    if (queue.isEmpty) {
      return const Center(
        child: Text('Desktop queue is empty', style: TextStyle(color: Colors.white38)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: queue.length,
      itemBuilder: (context, index) {
        final item = queue[index];
        final isPlayingThis = (index == client.state.currentIndex);

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          color: isPlayingThis
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.15)
              : const Color(0xFF1B1D24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: isPlayingThis
                ? BorderSide(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5))
                : BorderSide.none,
          ),
          child: ListTile(
            leading: Icon(
              isPlayingThis && client.state.isPlaying
                  ? Icons.graphic_eq
                  : Icons.music_note,
              color: isPlayingThis ? Theme.of(context).colorScheme.primary : Colors.white38,
            ),
            title: Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: isPlayingThis ? FontWeight.bold : FontWeight.normal,
                color: isPlayingThis ? Colors.white : Colors.white70,
              ),
            ),
            subtitle: Text(
              item.album.isNotEmpty ? '${item.artist} • ${item.album}' : item.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Colors.white38),
            ),
            trailing: item.lyrics.isNotEmpty
                ? const Icon(Icons.subtitles, size: 16, color: Colors.greenAccent)
                : null,
            onTap: () {
              client.jumpToIndex(index);
              _tabController.animateTo(0);
            },
          ),
        );
      },
    );
  }
}
