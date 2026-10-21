class DiaryEntry {
  const DiaryEntry({
    required this.timestampUtc,
    required this.text,
  });

  final DateTime timestampUtc;
  final String text;
}
