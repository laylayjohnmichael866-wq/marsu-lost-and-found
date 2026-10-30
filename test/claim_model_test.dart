import 'package:flutter_test/flutter_test.dart';
import 'package:marsu_lost_and_found/models/claim_model.dart';

void main() {
  final baseMap = <String, dynamic>{
    'id': 'claim-1',
    'report_id': 'found-1',
    'claimant_id': 'user-a',
    'claimant_name': 'User A',
    'claimant_contact': '09171234567',
    'claimant_contact_hidden': 'true',
    'private_claim_details': 'Has a red mark on the left shoe.',
    'status': 'pending',
    'created_at': '2026-10-30T08:00:00.000Z',
  };

  test('reads the claimant contact and text hidden flag', () {
    final claim = ClaimModel.fromMap(baseMap);

    expect(claim.claimantContact, '09171234567');
    expect(claim.claimantContactHidden, isTrue);
    expect(claim.status, ClaimStatus.pending);
  });

  test('accepts boolean hidden values from legacy rows', () {
    final claim = ClaimModel.fromMap({
      ...baseMap,
      'claimant_contact_hidden': false,
    });

    expect(claim.claimantContactHidden, isFalse);
  });

  test('serializes contact and hidden flag for the current schema', () {
    final claim = ClaimModel.fromMap(baseMap);
    final map = claim.toMap();

    expect(map['claimant_contact'], '09171234567');
    expect(map['claimant_contact_hidden'], isTrue);
    expect(map['report_id'], 'found-1');
    expect(map['item_report_id'], 'found-1');
    expect(map['claimant_id'], 'user-a');
  });

  test('falls back to the legacy item_report_id column', () {
    final claim = ClaimModel.fromMap({
      ...baseMap,
      'report_id': null,
      'item_report_id': 'found-legacy',
    });

    expect(claim.reportId, 'found-legacy');
  });
}
