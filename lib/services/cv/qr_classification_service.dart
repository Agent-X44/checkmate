import '../../models/omr/qr_data.dart';

class QrClassificationService {
  static String normalizeJoinCode(String value) {
    final cleaned = value
        .replaceAll(RegExp(r'[^A-Za-z0-9]'), '')
        .trim()
        .toUpperCase();
    return cleaned;
  }

  static String? extractInvitationCodeFromQr(QrData qrData) {
    final candidates = <String>[
      qrData.sheetIdentifier,
      qrData.examTitle,
      qrData.studentName,
    ];

    for (final raw in candidates) {
      final inviteCode = extractInviteCode(raw);
      if (inviteCode != null) return inviteCode;
    }

    return null;
  }

  static String? extractInviteCode(String raw) {
    final clean = raw.trim();
    if (clean.isEmpty) return null;

    if (clean.contains('code=')) {
      final uri = Uri.tryParse(clean);
      if (uri != null) {
        final codeParam = uri.queryParameters['code'] ?? uri.queryParameters['joinCode'];
        if (codeParam != null && codeParam.trim().isNotEmpty) {
          final normalized = normalizeJoinCode(codeParam);
          if (normalized.length >= 5 && normalized.length <= 8) return normalized;
        }
      }
    }

    final uri = Uri.tryParse(clean);
    if (uri != null && uri.scheme.isNotEmpty) {
      final codeParam = uri.queryParameters['code'] ?? uri.queryParameters['joinCode'];
      if (codeParam != null && codeParam.trim().isNotEmpty) {
        final normalized = normalizeJoinCode(codeParam);
        if (normalized.length >= 5 && normalized.length <= 8) return normalized;
      }
      if (uri.pathSegments.isNotEmpty) {
        final segments = uri.pathSegments.where((s) => s.trim().isNotEmpty).toList();
        if (segments.isNotEmpty) {
          final lastSegment = normalizeJoinCode(segments.last);
          if (RegExp(r'^[A-Z0-9]{5,8}$').hasMatch(lastSegment) &&
              !lastSegment.startsWith('SHEET') &&
              !lastSegment.contains('UNKNOWN')) {
            return lastSegment;
          }
        }
      }
    }

    final normalizedClean = normalizeJoinCode(clean);
    if (normalizedClean.length >= 5 && normalizedClean.length <= 8 &&
        !normalizedClean.startsWith('SHEET') &&
        !normalizedClean.contains('UNKNOWN') &&
        !normalizedClean.contains('CM50') &&
        !normalizedClean.contains('PY5')) {
      return normalizedClean;
    }

    if (clean.toUpperCase().contains('CODE') || clean.toUpperCase().contains('JOIN')) {
      final match = RegExp(r'[A-Z0-9]{5,8}').firstMatch(
        clean.toUpperCase().replaceAll('CODE', '').replaceAll('JOIN', '').replaceAll(':', '').trim(),
      );
      if (match != null) {
        final normalized = normalizeJoinCode(match.group(0)!);
        if (normalized.length >= 5 && normalized.length <= 8) return normalized;
      }
    }

    return null;
  }
}
