import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Backs out of [MenuPage].
///
/// Not `tester.pageBack()`. That helper hunts for a `BackButton` or a
/// `CupertinoNavigationBarBackButton`, and the menu header's back control is
/// neither: it is a bordered circle drawn by `_CircleIconButton`, chosen so the
/// arrow reads against a photograph. Three suites walked into the same wall
/// when the header was restyled, which is why this lives here rather than being
/// written out three times.
Future<void> menuPageBack(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.arrow_back_rounded).first);
  await tester.pumpAndSettle();
}
