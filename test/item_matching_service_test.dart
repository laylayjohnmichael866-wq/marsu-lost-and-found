import 'package:flutter_test/flutter_test.dart';
import 'package:marsu_lost_and_found/models/item_report_model.dart';
import 'package:marsu_lost_and_found/services/item_matching_service.dart';

void main() {
  ItemReport report({
    required String id,
    required String ownerId,
    required ReportType type,
    required String name,
    required String category,
    required String description,
    required String location,
    required DateTime date,
    ItemStatus status = ItemStatus.open,
  }) {
    return ItemReport(
      id: id,
      ownerId: ownerId,
      ownerName: ownerId,
      reportType: type,
      itemName: name,
      category: category,
      description: description,
      incidentDate: date,
      generalLocation: location,
      status: status,
      createdAt: date,
    );
  }

  final lostShoes = report(
    id: 'lost-shoes',
    ownerId: 'user-a',
    type: ReportType.lost,
    name: 'Black Rubber Shoes',
    category: 'Other',
    description:
        'Left my black rubber shoes near the gym entrance after PE class.',
    location: 'Gymnasium Entrance',
    date: DateTime(2026, 10, 30, 8),
  );

  final foundShoes = report(
    id: 'found-shoes',
    ownerId: 'user-b',
    type: ReportType.found,
    name: 'Rubber Shoes',
    category: 'Other',
    description: 'Found black rubber shoes near the gym.',
    location: 'Near Gymnasium',
    date: DateTime(2026, 10, 30, 10),
  );

  test('matches lost shoes with a similar found report', () {
    final matches = ItemMatchingService.matchesForLostItem(lostShoes, [
      lostShoes,
      foundShoes,
    ]);

    expect(matches, hasLength(1));
    expect(matches.single.foundItem.id, 'found-shoes');
    expect(matches.single.score, greaterThanOrEqualTo(0.55));
    expect(matches.single.confidencePercent, greaterThanOrEqualTo(55));
    expect(matches.single.reasons.length, greaterThanOrEqualTo(2));
  });

  test('finds the lost report from a found report submission', () {
    final matches = ItemMatchingService.matchesForFoundItem(foundShoes, [
      lostShoes,
      foundShoes,
    ]);

    expect(matches, hasLength(1));
    expect(matches.single.lostItem.id, 'lost-shoes');
  });

  test('does not match unrelated items', () {
    final foundUmbrella = report(
      id: 'found-umbrella',
      ownerId: 'user-b',
      type: ReportType.found,
      name: 'Blue Umbrella',
      category: 'Other',
      description: 'Found a blue folding umbrella in the library.',
      location: 'Library',
      date: DateTime(2026, 10, 30, 10),
    );

    final matches = ItemMatchingService.matchesForLostItem(lostShoes, [
      lostShoes,
      foundUmbrella,
    ]);

    expect(matches, isEmpty);
  });

  test('does not match reports from the same owner', () {
    final ownFoundShoes = report(
      id: 'own-found-shoes',
      ownerId: 'user-a',
      type: ReportType.found,
      name: 'Rubber Shoes',
      category: 'Other',
      description: 'Found black rubber shoes near the gym.',
      location: 'Near Gymnasium',
      date: DateTime(2026, 10, 30, 10),
    );

    final matches = ItemMatchingService.matchesForLostItem(lostShoes, [
      lostShoes,
      ownFoundShoes,
    ]);

    expect(matches, isEmpty);
  });

  test('does not match items with distant locations and dates', () {
    final distantFoundShoes = report(
      id: 'distant-found-shoes',
      ownerId: 'user-b',
      type: ReportType.found,
      name: 'Black Rubber Shoes',
      category: 'Other',
      description: 'Found a pair of shoes.',
      location: 'Main Gate',
      date: DateTime(2026, 12, 30, 10),
    );

    final matches = ItemMatchingService.matchesForLostItem(lostShoes, [
      lostShoes,
      distantFoundShoes,
    ]);

    expect(matches, isEmpty);
  });

  test('ignores returned or closed reports', () {
    final returnedShoes = report(
      id: 'returned-shoes',
      ownerId: 'user-b',
      type: ReportType.found,
      name: 'Rubber Shoes',
      category: 'Other',
      description: 'Found black rubber shoes near the gym.',
      location: 'Near Gymnasium',
      date: DateTime(2026, 10, 30, 10),
      status: ItemStatus.returned,
    );

    final matches = ItemMatchingService.matchesForLostItem(lostShoes, [
      lostShoes,
      returnedShoes,
    ]);

    expect(matches, isEmpty);
  });
}
