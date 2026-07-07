import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/app/zopiq_app.dart';

void main() {
  testWidgets('App boots into the design showcase with themed components',
      (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: ZopiqApp()));
    // Not pumpAndSettle: the shimmer skeleton animates forever, so the tree
    // never fully settles. One frame is enough to build the showcase.
    await tester.pump();

    // The showcase renders and pulls in design-system widgets.
    expect(find.text('zopiq_ui'), findsOneWidget);
    expect(find.byType(ZopiqButton), findsWidgets);
    expect(find.byType(ZopiqCard), findsOneWidget);
    expect(find.byType(ZopiqVegIndicator), findsOneWidget);
  });
}
