import 'package:checkmate/models/omr/qr_data.dart';
import 'package:checkmate/services/cv/qr_classification_service.dart';
import 'package:checkmate/services/deep_link_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final inviteToken = List.filled(64, 'a').join();

  test('course invites use a private token in the hosted app-link landing', () {
    final invite = Uri.parse(DeepLinkService.buildInviteLink(inviteToken));
    expect(invite.scheme, 'https');
    expect(invite.host, DeepLinkService.inviteHost);
    expect(invite.path, '/join');
    expect(invite.queryParameters['inviteToken'], inviteToken);
    expect(invite.queryParameters.containsKey('code'), isFalse);
  });

  test('custom app links carry and parse the private invite token', () {
    final link = Uri.parse(DeepLinkService.buildCustomSchemeLink(inviteToken));

    expect(link.scheme, 'checkmate');
    expect(link.host, 'join');
    expect(DeepLinkService.extractInviteToken(link), inviteToken);
  });

  test('legacy course-code invite links are not treated as private invitations',
      () {
    final link = Uri.parse('checkmate://join?joinCode=JOIN42');

    expect(DeepLinkService.extractInviteToken(link), isNull);
  });

  test('HTTPS invitation QR codes classify the opaque invite token', () {
    final link = DeepLinkService.buildInviteLink(inviteToken);
    final qrData = QrData(
      studentName: 'Invitation',
      examCode: link,
      course: 'CheckMate',
      examTitle: link,
      sheetIdentifier: link,
    );

    expect(QrClassificationService.extractInvitationCodeFromQr(qrData),
        inviteToken);
  });

  test('scanner recognizes plain course invite codes from a QR payload', () {
    final qrData = QrData.fromRaw('join-42');

    expect(
      QrClassificationService.extractInvitationCodeFromQr(qrData),
      'JOIN42',
    );
  });

  test('legacy code links and malformed links are not treated as invitations',
      () {
    expect(
      DeepLinkService.extractJoinCode(Uri.parse('https://example.com/join')),
      isNull,
    );
    expect(
      QrClassificationService.extractInviteCode(
        'https://noelpi-checkmate-backend.hf.space/join?code=JOIN42',
      ),
      isNull,
    );
  });
}
