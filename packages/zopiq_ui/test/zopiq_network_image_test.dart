import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

const Key _fallbackKey = Key('fallback');

Widget _host(String url) {
  return MaterialApp(
    theme: ZopiqTheme.light,
    home: Scaffold(
      body: SizedBox(
        width: 200,
        height: 100,
        child: ZopiqNetworkImage(
          url: url,
          fallback: const ColoredBox(key: _fallbackKey, color: Color(0xFF123456)),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('an empty url renders the fallback without touching the network',
      (WidgetTester tester) async {
    await tester.pumpWidget(_host(''));

    expect(find.byKey(_fallbackKey), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('a failing url degrades to the fallback, never a broken image',
      (WidgetTester tester) async {
    // flutter_test stubs HttpClient to return 400 for every request, so this
    // exercises the real errorBuilder path.
    await tester.pumpWidget(_host('https://example.invalid/missing.jpg'));
    await tester.pumpAndSettle();

    expect(find.byKey(_fallbackKey), findsOneWidget);
  });
}
