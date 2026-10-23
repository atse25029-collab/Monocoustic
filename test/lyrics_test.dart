import 'package:flutter_test/flutter_test.dart';
import 'package:monocoustic/core/lyrics/lrc_parser.dart';
import 'package:monocoustic/core/lyrics/smi_parser.dart';
import 'package:monocoustic/core/lyrics/lyrics_manager.dart';

void main() {
  group('LrcParser Tests', () {
    test('parses standard timestamped lines correctly', () {
      const lrc = '''
[ti:Sample Song]
[ar:Artist Name]
[00:05.50]First line of lyrics
[00:10.25]Second line of lyrics
[01:02.00]One minute line
''';
      final result = LrcParser.parse(lrc);
      expect(result.length, 3);
      expect(result[0].timestamp.inMilliseconds, 5500);
      expect(result[0].text, 'First line of lyrics');
      expect(result[1].timestamp.inMilliseconds, 10250);
      expect(result[1].text, 'Second line of lyrics');
      expect(result[2].timestamp.inMilliseconds, 62000);
      expect(result[2].text, 'One minute line');
    });

    test('parses multi-timestamp single lines', () {
      const lrc = '''
[00:15.00][00:30.00]Repeated chorus line
''';
      final result = LrcParser.parse(lrc);
      expect(result.length, 2);
      expect(result[0].timestamp.inMilliseconds, 15000);
      expect(result[0].text, 'Repeated chorus line');
      expect(result[1].timestamp.inMilliseconds, 30000);
      expect(result[1].text, 'Repeated chorus line');
    });

    test('applies offset correctly', () {
      const lrc = '''
[offset:+500]
[00:02.00]Line with offset
''';
      final result = LrcParser.parse(lrc);
      expect(result.length, 1);
      expect(result[0].timestamp.inMilliseconds, 2500);
    });
  });

  group('SmiParser Tests', () {
    test('parses standard SAMI format with class and cleans HTML', () {
      const smi = '''
<SAMI>
<HEAD>
<TITLE>SAMI Test</TITLE>
<STYLE TYPE="text/css">
<!--
.KRCC { Name: Korean; lang: ko-KR; }
-->
</STYLE>
</HEAD>
<BODY>
<SYNC Start=3500><P Class=KRCC><font color="yellow">Hello</font> <b>World</b><br>Lyrics!
<SYNC Start=8000><P Class=KRCC>&nbsp;
</BODY>
</SAMI>
''';
      final result = SmiParser.parse(smi);
      expect(result.isNotEmpty, true);
      expect(result[0].timestamp.inMilliseconds, 3500);
      expect(result[0].text, 'Hello World Lyrics!');
      expect(result[1].timestamp.inMilliseconds, 8000);
      expect(result[1].text, ''); // Cleaned &nbsp;
    });

    test('extracts primary text and translation when multiple classes exist', () {
      const smi = '''
<SYNC Start=12000><P Class=KRCC>안녕하세요
<SYNC Start=12000><P Class=ENCC>Hello there
<SYNC Start=20000><P Class=KRCC>감사합니다
<SYNC Start=20000><P Class=ENCC>Thank you
''';
      final result = SmiParser.parse(smi);
      expect(result.length, 2);
      expect(result[0].timestamp.inMilliseconds, 12000);
      expect(result[0].text, '안녕하세요');
      expect(result[0].translation, 'Hello there');

      expect(result[1].timestamp.inMilliseconds, 20000);
      expect(result[1].text, '감사합니다');
      expect(result[1].translation, 'Thank you');
    });

    test('handles hybrid SAMI with bracketed timestamp prefixes and entity decoding', () {
      const smi = '''
[00:15.00] <SYNC Start=27011><P class='en1'>&nbsp;
[00:15.00] <SYNC Start=27011><P class='en1'>&#9834; Having the time of your life &#9834;
[00:16.00] <SYNC Start=30745><P class='en1'>See that girl, watch that scene
[00:20.00] <SYNC Start=34873><P class='en1'>Dig in the dancing queen
''';
      final result = SmiParser.parse(smi);
      expect(result.length, 3);
      expect(result[0].timestamp.inMilliseconds, 27011);
      expect(result[0].text, '♪ Having the time of your life ♪');
      expect(result[1].timestamp.inMilliseconds, 30745);
      expect(result[1].text, 'See that girl, watch that scene');
      expect(result[2].timestamp.inMilliseconds, 34873);
      expect(result[2].text, 'Dig in the dancing queen');
    });
  });

  group('LyricsManager Active Index Lookup Tests', () {
    test('accurately locates active lyric using binary search', () {
      const lrc = '''
[00:05.00]Line 1
[00:10.00]Line 2
[00:20.00]Line 3
[00:35.00]Line 4
''';
      final lyrics = LrcParser.parse(lrc);

      // Before first line
      expect(LyricsManager.findActiveIndex(lyrics, const Duration(seconds: 2)), -1);

      // Exactly at first line
      expect(LyricsManager.findActiveIndex(lyrics, const Duration(seconds: 5)), 0);

      // Between line 1 and line 2
      expect(LyricsManager.findActiveIndex(lyrics, const Duration(seconds: 8)), 0);

      // Exactly at line 2
      expect(LyricsManager.findActiveIndex(lyrics, const Duration(seconds: 10)), 1);

      // Between line 3 and 4
      expect(LyricsManager.findActiveIndex(lyrics, const Duration(seconds: 25)), 2);

      // Beyond last line
      expect(LyricsManager.findActiveIndex(lyrics, const Duration(seconds: 50)), 3);
    });
  });
}
