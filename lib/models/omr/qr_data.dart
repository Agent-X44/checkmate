class QrData {
  final String studentName;
  final String examCode;
  final String course;
  final String examTitle;
  final String? templateName;
  final String sheetIdentifier;

  QrData({
    required this.studentName,
    required this.examCode,
    required this.course,
    required this.examTitle,
    required this.sheetIdentifier,
    this.templateName,
  });

  factory QrData.fromRaw(String raw) {
    final parts = raw.split(',');
    if (parts.length >= 4) {
      return QrData(
        studentName: parts[0].trim(),
        examCode: parts[1].trim(),
        course: parts[2].trim(),
        examTitle: parts[3].trim(),
        sheetIdentifier: parts[1].trim(),
        templateName: parts.length >= 5 ? parts[4].trim() : null,
      );
    }

    if (raw.isNotEmpty) {
      return QrData(
        studentName: 'Resolving Student...',
        examCode: raw.trim(),
        course: 'Checkmate LMS',
        examTitle: 'Assessment: $raw',
        sheetIdentifier: raw.trim(),
        templateName: "Standard 50 Questions",
      );
    }

    return QrData(
      studentName: 'Unknown',
      examCode: 'UNKNOWN',
      course: 'Unknown',
      examTitle: 'Unknown',
      sheetIdentifier: 'UNKNOWN',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'studentName': studentName,
      'examCode': examCode,
      'course': course,
      'examTitle': examTitle,
      'sheetIdentifier': sheetIdentifier,
      'templateName': templateName,
    };
  }

  @override
  String toString() => '$studentName ($sheetIdentifier)';
}
