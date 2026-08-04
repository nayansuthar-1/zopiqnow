import 'package:flutter/foundation.dart';

/// What went wrong, from the closed set migration 0095 accepts.
///
/// The wire values are the database's; [label] is what the customer reads. The
/// two are kept apart on purpose — the console filters and sorts on the value,
/// and the label can be reworded without a migration.
enum IssueCategory {
  missingItem('missing_item', 'Something was missing'),
  wrongItem('wrong_item', 'I got the wrong item'),
  quality('quality', 'The food wasn\'t good'),
  damaged('damaged', 'It arrived spilled or damaged'),
  late('late', 'It arrived very late'),
  neverArrived('never_arrived', 'It never arrived'),
  rider('rider', 'A problem with the delivery partner'),
  payment('payment', 'A problem with the payment'),
  other('other', 'Something else');

  const IssueCategory(this.wire, this.label);

  final String wire;
  final String label;

  /// An unknown wire value reads as [other]. A build older than a category added
  /// later should show the customer their own complaint under a vague heading,
  /// not crash on the way to it.
  static IssueCategory fromWire(String wire) => values.firstWhere(
    (IssueCategory c) => c.wire == wire,
    orElse: () => other,
  );
}

/// One complaint the customer raised about one order.
///
/// Deliberately not a refund and not a status: raising one moves no money and
/// changes nothing about the order. It is a statement that lands in a queue, and
/// [adminNote] is the answer that comes back.
@immutable
class OrderIssue {
  const OrderIssue({
    required this.id,
    required this.category,
    required this.body,
    required this.isResolved,
    required this.createdAt,
    this.resolvedAt,
    this.adminNote,
  });

  factory OrderIssue.fromJson(Map<String, dynamic> json) {
    return OrderIssue(
      id: (json['id'] as num).toInt(),
      category: IssueCategory.fromWire(json['category'] as String),
      body: json['body'] as String? ?? '',
      isResolved: (json['status'] as String?) == 'resolved',
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      resolvedAt: switch (json['resolved_at']) {
        final String s => DateTime.parse(s).toLocal(),
        _ => null,
      },
      adminNote: json['admin_note'] as String?,
    );
  }

  final int id;
  final IssueCategory category;

  /// What they typed, or empty. A category on its own is a complete complaint.
  final String body;

  final bool isResolved;
  final DateTime createdAt;
  final DateTime? resolvedAt;

  /// What somebody at Zopiqnow wrote back. Null until the ticket is closed, and
  /// null after it is closed if they closed it without a word.
  final String? adminNote;
}

/// A complaint the service refused, with its own sentence — "You have already
/// reported this order.", "That is a lot of reports at once." Those are answers,
/// not errors to bury under a generic apology.
class OrderIssueFailure implements Exception {
  const OrderIssueFailure([
    this.message = 'We couldn\'t send that just now. Please try again.',
  ]);

  final String message;
}
