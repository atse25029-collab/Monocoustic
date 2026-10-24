import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Controls Windows master system audio volume via native CoreAudio helper.
class WinVolumeHelper {
  static String? _cachedExePath;

  /// Locates the SetVol.exe helper binary
  static String? _findHelperPath() {
    if (!Platform.isWindows || Platform.environment.containsKey('FLUTTER_TEST')) return null;
    if (_cachedExePath != null && File(_cachedExePath!).existsSync()) {
      return _cachedExePath;
    }

    final currentExeDir = File(Platform.resolvedExecutable).parent.path;

    final candidates = [
      p.join(currentExeDir, 'SetVol.exe'),
      p.join(currentExeDir, 'data', 'flutter_assets', 'assets', 'bin', 'SetVol.exe'),
      p.join(Directory.current.path, 'assets', 'bin', 'SetVol.exe'),
      p.join(Directory.current.path, 'windows', 'runner', 'SetVol.exe'),
    ];

    for (final path in candidates) {
      if (File(path).existsSync()) {
        _cachedExePath = path;
        return path;
      }
    }

    return null;
  }

  /// Sets Windows system master volume (0.0 to 1.0)
  static Future<void> setMasterVolume(double volume) async {
    if (!Platform.isWindows) return;
    final helper = _findHelperPath();
    if (helper == null) return;

    try {
      final volInt = (volume.clamp(0.0, 1.0) * 100).round();
      await Process.run(helper, [volInt.toString()]);
    } catch (e) {
      debugPrint('Error setting Windows system volume: $e');
    }
  }

  /// Gets current Windows system master volume (returns 0.0 to 1.0, or null on error)
  static Future<double?> getMasterVolume() async {
    if (!Platform.isWindows) return null;
    final helper = _findHelperPath();
    if (helper == null) return null;

    try {
      final res = await Process.run(helper, []);
      final out = res.stdout.toString().trim();
      final volInt = int.tryParse(out);
      if (volInt != null) {
        return (volInt / 100.0).clamp(0.0, 1.0);
      }
    } catch (e) {
      debugPrint('Error getting Windows system volume: $e');
    }
    return null;
  }
}
