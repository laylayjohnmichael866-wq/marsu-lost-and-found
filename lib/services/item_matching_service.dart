import 'dart:math';

import '../models/item_report_model.dart';

class ItemMatch {
  final ItemReport lostItem;
  final ItemReport foundItem;
  final double score;
  final List<String> reasons;

  const ItemMatch({
    required this.lostItem,
    required this.foundItem,
    required this.score,
    required this.reasons,
  });

  int get confidencePercent => (score * 100).round();
}

class ItemMatchingService {
  static const double minimumScore = 0.55;

  static const Set<String> _stopWords = {
    'a',
    'an',
    'and',
    'are',
    'at',
    'found',
    'from',
    'in',
    'is',
    'it',
    'item',
    'items',
    'lost',
    'my',
    'near',
    'of',
    'on',
    'or',
    'the',
    'this',
    'to',
    'was',
    'were',
    'with',
  };

  static List<ItemMatch> matchesForLostItem(
    ItemReport lostItem,
    Iterable<ItemReport> reports,
  ) {
    if (lostItem.reportType != ReportType.lost || !_isActive(lostItem)) {
      return const [];
    }

    final matches = <ItemMatch>[];
    for (final foundItem in reports) {
      if (foundItem.reportType != ReportType.found ||
          foundItem.id == lostItem.id ||
          foundItem.ownerId == lostItem.ownerId ||
          !_isActive(foundItem)) {
        continue;
      }

      final evaluation = _evaluate(lostItem, foundItem);
      if (evaluation.score >= minimumScore && evaluation.reasons.length >= 2) {
        matches.add(
          ItemMatch(
            lostItem: lostItem,
            foundItem: foundItem,
            score: evaluation.score,
            reasons: evaluation.reasons,
          ),
        );
      }
    }

    matches.sort((a, b) => b.score.compareTo(a.score));
    return matches;
  }

  static List<ItemMatch> matchesForFoundItem(
    ItemReport foundItem,
    Iterable<ItemReport> reports,
  ) {
    if (foundItem.reportType != ReportType.found || !_isActive(foundItem)) {
      return const [];
    }

    final matches = <ItemMatch>[];
    for (final lostItem in reports) {
      if (lostItem.reportType != ReportType.lost ||
          lostItem.id == foundItem.id ||
          lostItem.ownerId == foundItem.ownerId ||
          !_isActive(lostItem)) {
        continue;
      }

      final evaluation = _evaluate(lostItem, foundItem);
      if (evaluation.score >= minimumScore && evaluation.reasons.length >= 2) {
        matches.add(
          ItemMatch(
            lostItem: lostItem,
            foundItem: foundItem,
            score: evaluation.score,
            reasons: evaluation.reasons,
          ),
        );
      }
    }

    matches.sort((a, b) => b.score.compareTo(a.score));
    return matches;
  }

  static bool _isActive(ItemReport item) {
    return item.status != ItemStatus.returned &&
        item.status != ItemStatus.closed;
  }

  static _MatchEvaluation _evaluate(ItemReport lostItem, ItemReport foundItem) {
    final nameScore = _similarity(lostItem.itemName, foundItem.itemName);
    final categoryScore =
        _normalized(lostItem.category) == _normalized(foundItem.category)
        ? 1.0
        : 0.0;
    final locationScore = _similarity(
      lostItem.generalLocation,
      foundItem.generalLocation,
    );
    final dateScore = _dateSimilarity(
      lostItem.incidentDate,
      foundItem.incidentDate,
    );
    final descriptionScore = _similarity(
      lostItem.description,
      foundItem.description,
    );

    final score =
        nameScore * 0.30 +
        categoryScore * 0.20 +
        locationScore * 0.20 +
        dateScore * 0.12 +
        descriptionScore * 0.18;

    final hasLocationOrDateSignal = locationScore >= 0.45 || dateScore >= 0.55;
    final hasStrongContentSignal = nameScore >= 0.75 && descriptionScore >= 0.5;

    final reasons = <String>[];
    if (nameScore >= 0.4) reasons.add('similar item name');
    if (categoryScore == 1) reasons.add('same category');
    if (locationScore >= 0.45) reasons.add('similar location');
    if (dateScore >= 0.55) reasons.add('close incident dates');
    if (descriptionScore >= 0.3) reasons.add('description keywords overlap');

    return _MatchEvaluation(
      score: hasLocationOrDateSignal || hasStrongContentSignal
          ? score.clamp(0.0, 1.0).toDouble()
          : 0,
      reasons: reasons,
    );
  }

  static double _dateSimilarity(DateTime first, DateTime second) {
    final days = first.difference(second).inDays.abs();
    if (days <= 1) return 1;
    if (days <= 3) return 0.8;
    if (days <= 7) return 0.55;
    if (days <= 14) return 0.25;
    return 0;
  }

  static double _similarity(String first, String second) {
    final normalizedFirst = _normalized(first);
    final normalizedSecond = _normalized(second);
    if (normalizedFirst.isEmpty || normalizedSecond.isEmpty) return 0;
    if (normalizedFirst == normalizedSecond) return 1;

    final firstTokens = _tokens(normalizedFirst);
    final secondTokens = _tokens(normalizedSecond);
    if (firstTokens.isEmpty || secondTokens.isEmpty) return 0;

    final intersection = firstTokens.intersection(secondTokens).length;
    if (intersection == 0) return 0;

    final union = firstTokens.union(secondTokens).length;
    final jaccard = intersection / union;
    final containment =
        intersection / min(firstTokens.length, secondTokens.length);
    final phraseMatch =
        normalizedFirst.contains(normalizedSecond) ||
            normalizedSecond.contains(normalizedFirst)
        ? 0.85
        : 0.0;

    return max(jaccard, max(containment * 0.9, phraseMatch));
  }

  static Set<String> _tokens(String normalizedText) {
    return normalizedText
        .split(' ')
        .where((token) => token.length > 1 && !_stopWords.contains(token))
        .toSet();
  }

  static String _normalized(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}

class _MatchEvaluation {
  final double score;
  final List<String> reasons;

  const _MatchEvaluation({required this.score, required this.reasons});
}
