class LyricLine {
  final Duration timestamp;
  final String text;
  final String? translation;

  const LyricLine({
    required this.timestamp,
    required this.text,
    this.translation,
  });

  Map<String, dynamic> toJson() {
    return {
      'ms': timestamp.inMilliseconds,
      'text': text,
      if (translation != null) 'trans': translation,
    };
  }

  factory LyricLine.fromJson(Map<String, dynamic> json) {
    return LyricLine(
      timestamp: Duration(milliseconds: json['ms'] as int? ?? 0),
      text: json['text'] as String? ?? '',
      translation: json['trans'] as String?,
    );
  }

  @override
  String toString() => '[${timestamp.inMilliseconds}ms] $text${translation != null ? " ($translation)" : ""}';
}
