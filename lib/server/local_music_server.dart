import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../core/models/playback_state.dart';
import '../core/models/remote_protocol.dart';

typedef CommandHandler = void Function(String command, Map<String, dynamic>? data);

class NetworkAddressInfo {
  final String interfaceName;
  final String ip;
  final bool isVirtual;

  const NetworkAddressInfo({
    required this.interfaceName,
    required this.ip,
    this.isVirtual = false,
  });
}

class LocalMusicServer {
  HttpServer? _server;
  final List<WebSocket> _clients = [];
  CommandHandler? onCommandReceived;
  PlaybackStateSnapshot Function()? getStateSnapshot;

  int _port = 8080;
  int get port => _port;
  bool get isRunning => _server != null;

  /// Starts the local HTTP & WebSocket server.
  Future<int> start({int port = 8080}) async {
    await stop();

    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    } catch (_) {
      // If port is busy, fallback to ephemeral/open port
      _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    }

    _port = _server!.port;
    _server!.listen(_handleHttpRequest);
    return _port;
  }

  /// Stops the server and closes client connections.
  Future<void> stop() async {
    final clientsToClose = List<WebSocket>.from(_clients);
    _clients.clear();
    for (final client in clientsToClose) {
      try {
        await client.close();
      } catch (_) {}
    }
    await _server?.close(force: true);
    _server = null;
  }

  /// Retrieves detailed network interface information, prioritizing physical Wi-Fi and Ethernet.
  static Future<List<NetworkAddressInfo>> getDetailedNetworkInterfaces() async {
    final List<NetworkAddressInfo> list = [];
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );

      for (final interface in interfaces) {
        final lowerName = interface.name.toLowerCase();
        final isVirtual = lowerName.contains(
          RegExp(r'vmware|virtual|vbox|vethernet|wsl|hyper-v|loopback|bluetooth|teredo|tap|vpn'),
        );

        for (final addr in interface.addresses) {
          if (!addr.isLoopback) {
            list.add(
              NetworkAddressInfo(
                interfaceName: interface.name,
                ip: addr.address,
                isVirtual: isVirtual,
              ),
            );
          }
        }
      }
    } catch (_) {}

    // Sort:
    // 1. Physical Wi-Fi/WLAN first (best for phone hotspot/home Wi-Fi)
    // 2. Physical Ethernet
    // 3. Other physical
    // 4. Virtual adapters (VMware, WSL, etc.) last
    list.sort((a, b) {
      if (a.isVirtual != b.isVirtual) {
        return a.isVirtual ? 1 : -1;
      }
      final aWifi = a.interfaceName.toLowerCase().contains(RegExp(r'wi-fi|wlan|wireless'));
      final bWifi = b.interfaceName.toLowerCase().contains(RegExp(r'wi-fi|wlan|wireless'));
      if (aWifi != bWifi) {
        return aWifi ? -1 : 1;
      }
      return a.interfaceName.compareTo(b.interfaceName);
    });

    if (list.isEmpty) {
      list.add(const NetworkAddressInfo(
        interfaceName: 'Loopback',
        ip: '127.0.0.1',
        isVirtual: false,
      ));
    }

    return list;
  }

  /// Retrieves list of valid local IPv4 LAN addresses with physical Wi-Fi prioritized at the top.
  static Future<List<String>> getLocalIpAddresses() async {
    final detailed = await getDetailedNetworkInterfaces();
    return detailed.map((d) => d.ip).toList();
  }

  void _handleHttpRequest(HttpRequest request) async {
    // Add CORS headers for flexibility
    request.response.headers.add('Access-Control-Allow-Origin', '*');
    request.response.headers.add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    request.response.headers.add('Access-Control-Allow-Headers', 'Content-Type');

    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.ok;
      await request.response.close();
      return;
    }

    final path = request.uri.path;

    if (path == '/ws') {
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        final socket = await WebSocketTransformer.upgrade(request);
        _handleNewClient(socket);
      } else {
        request.response.statusCode = HttpStatus.badRequest;
        await request.response.close();
      }
      return;
    }

    if (path == '/status') {
      final snapshot = getStateSnapshot?.call();
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'status': 'online',
        'server': 'Monocoustic Desktop',
        'playback': snapshot?.toJson(),
      }));
      await request.response.close();
      return;
    }

    if (path == '/album-art') {
      final snapshot = getStateSnapshot?.call();
      final artPath = snapshot?.currentSong?.albumArtPath;
      if (artPath != null) {
        final artFile = File(artPath);
        if (await artFile.exists()) {
          final isPng = artPath.toLowerCase().endsWith('.png');
          request.response.headers.contentType = isPng ? ContentType('image', 'png') : ContentType('image', 'jpeg');
          await request.response.addStream(artFile.openRead());
          await request.response.close();
          return;
        }
      }
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    request.response.statusCode = HttpStatus.notFound;
    await request.response.close();
  }

  void _handleNewClient(WebSocket socket) {
    _clients.add(socket);

    // Send initial full state immediately upon connection
    final snapshot = getStateSnapshot?.call();
    if (snapshot != null) {
      try {
        socket.add(RemoteProtocol.encodeEvent(RemoteProtocol.evtFullState, snapshot.toJson()));
      } catch (_) {}
    }

    socket.listen(
      (message) {
        if (message is String) {
          final decoded = RemoteProtocol.decodeMessage(message);
          if (decoded != null && decoded['type'] == 'command') {
            final cmd = decoded['action'] as String? ?? '';
            final data = decoded['data'] as Map<String, dynamic>?;

            if (cmd == RemoteProtocol.cmdRequestSync) {
              final currentSnap = getStateSnapshot?.call();
              if (currentSnap != null) {
                try {
                  socket.add(RemoteProtocol.encodeEvent(
                    RemoteProtocol.evtFullState,
                    currentSnap.toJson(),
                  ));
                } catch (_) {}
              }
            } else {
              onCommandReceived?.call(cmd, data);
            }
          }
        }
      },
      onDone: () => _clients.remove(socket),
      onError: (_) => _clients.remove(socket),
      cancelOnError: true,
    );
  }

  /// Broadcast a raw event to all connected Android remote clients
  void broadcastEvent(String event, dynamic data) {
    if (_clients.isEmpty) return;
    final message = RemoteProtocol.encodeEvent(event, data);
    for (final client in List<WebSocket>.from(_clients)) {
      try {
        client.add(message);
      } catch (_) {
        _clients.remove(client);
      }
    }
  }

  /// Broadcast full state to all clients
  void broadcastFullState(PlaybackStateSnapshot snapshot) {
    broadcastEvent(RemoteProtocol.evtFullState, snapshot.toJson());
  }

  /// Broadcast high-frequency position ticks
  void broadcastPosition(int positionMs, int lyricIndex) {
    broadcastEvent(RemoteProtocol.evtPositionTick, {
      'pos': positionMs,
      'lyricIdx': lyricIndex,
    });
  }

  /// Broadcast quick volume change to clients
  void broadcastVolume(double volume) {
    broadcastEvent('volume', {'volume': volume});
  }

  int get connectedClientsCount => _clients.length;
}
