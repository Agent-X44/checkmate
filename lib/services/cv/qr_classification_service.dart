import '../../models/omr/qr_data.dart';
import '../deep_link_service.dart';

class QrClassificationService {
  static String normalizeJoinCode(String value) {
    final cleaned =
        value.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').trim().toUpperCase();
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
    if (DeepLinkService.isInviteToken(clean)) return clean.toLowerCase();

    final uri = Uri.tryParse(clean);
    if (uri != null && uri.scheme.isNotEmpty) {
      final token = DeepLinkService.extractInviteToken(uri);
      if (token != null) return token;
      if (uri.queryParameters.containsKey('joinCode') ||
          uri.queryParameters.containsKey('code')) {
        return null;
      }
      final code = DeepLinkService.extractJoinCode(uri);
      if (code != null && !_isSheetIdentifier(code)) return code;
    }

    final normalizedClean = normalizeJoinCode(clean);
    if (normalizedClean.length >= 5 &&
        normalizedClean.length <= 8 &&
        !normalizedClean.startsWith('SHEET') &&
        !normalizedClean.contains('UNKNOWN') &&
        !normalizedClean.contains('CM50') &&
        !normalizedClean.contains('PY5') &&
        !_isSheetIdentifier(normalizedClean)) {
      return normalizedClean;
    }

    if (clean.toUpperCase().contains('CODE') ||
        clean.toUpperCase().contains('JOIN')) {
      final match = RegExp(r'[A-Z0-9]{5,8}').firstMatch(
        clean
            .toUpperCase()
            .replaceAll('CODE', '')
            .replaceAll('JOIN', '')
            .replaceAll(':', '')
            .trim(),
      );
      if (match != null) {
        final normalized = normalizeJoinCode(match.group(0)!);
        if (normalized.length >= 5 && normalized.length <= 8) return normalized;
      }
    }

    return null;
  }

  static bool _isSheetIdentifier(String value) {
    return value.startsWith('CM-') ||
        value.startsWith('SHEET') ||
        value.contains('UNKNOWN') ||
        value.contains('CM50') ||
        value.contains('PY5');
  }
}
