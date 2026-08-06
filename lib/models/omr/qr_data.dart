class QrData {
  final String studentName;
  final String examCode;
  final String course;
  final String examTitle;
  final String? templateName;

  QrData({
    required this.studentName,
    required this.examCode,
    required this.course,
    required this.examTitle,
    this.templateName,
  });

  factory QrData.fromRaw(String raw) {
    // Expected format: "Name,ExamCode,Course,Title,TemplateName"
    final parts = raw.split(',');
    if (parts.length >= 4) {
      return QrData(
        studentName: parts[0].trim(),
        examCode: parts[1].trim(),
        course: parts[2].trim(),
        examTitle: parts[3].trim(),
        templateName: parts.length >= 5 ? parts[4].trim() : null,
      );
    }
    return QrData(
      studentName: 'Unknown',
      examCode: 'Unknown',
      course: 'Unknown',
      examTitle: 'Unknown',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'studentName': studentName,
      'examCode': examCode,
      'course': course,
      'examTitle': examTitle,
      'templateName': templateName,
    };
  }

  @override
  String toString() => '$studentName - $examTitle ($examCode) [$course] ${templateName ?? ""}';
}
