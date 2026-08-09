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
    // 1. Handle Legacy Format: "Name,ExamCode,Course,Title,TemplateName"
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

    // 2. Handle Optimized Payload (Single SheetID): e.g., "CM50-A-0001"
    if (raw.startsWith("CM") && raw.contains("-")) {
      final segments = raw.split('-');
      String templateInferred = "Unknown";
      if (segments[0] == "CM50") templateInferred = "Standard 50 Questions";
      
      final studentSerial = segments.length > 2 ? segments[2] : "Unknown";

      return QrData(
        studentName: 'Student #$studentSerial',
        examCode: raw.trim(), // The full ID is the exam code
        course: 'Checkmate LMS',
        examTitle: templateInferred,
        templateName: templateInferred,
      );
    }

    // 3. Fallback
    return QrData(
      studentName: raw.isEmpty ? 'Unknown' : 'ID: $raw',
      examCode: raw.isEmpty ? 'Unknown' : raw,
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
  String toString() =>
      '$studentName - $examTitle ($examCode) [$course] ${templateName ?? ""}';
}
