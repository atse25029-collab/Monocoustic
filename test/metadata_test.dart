import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:monocoustic/core/metadata/audio_metadata_reader.dart';

void main() {
  group('AudioMetadataReader Tests', () {
    test('cleans filename noise and extracts artist and title', () async {
      final meta = await AudioMetadataReader.read(
        'C:\\Music\\ABBA - Dancing Queen (Official Music Video)_256k.mp3',
      );
      expect(meta.artist, 'ABBA');
      expect(meta.title, 'Dancing Queen');
    });

    test('handles simple filename without hyphen separator', () async {
      final meta = await AudioMetadataReader.read('C:\\Music\\Imagine [Remastered].flac');
      expect(meta.title, 'Imagine');
      expect(meta.artist, 'Unknown Artist');
    });

    test('discovers folder album art if present', () async {
      final tempDir = await Directory.systemTemp.createTemp('monocoustic_test_');
      final dummyAudio = File('${tempDir.path}\\Song.mp3');
      await dummyAudio.writeAsString('dummy');
      final dummyCover = File('${tempDir.path}\\cover.jpg');
      await dummyCover.writeAsString('fake_image_data');

      final meta = await AudioMetadataReader.read(dummyAudio.path);
      expect(meta.albumArtPath, dummyCover.path);

      await tempDir.delete(recursive: true);
    });
  });
}
