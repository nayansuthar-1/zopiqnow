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

    // `pumpAndSettle` alone is not enough any more, and that is a property of
    // the provider rather than a flake. `ZopiqNetworkImage` is backed by
    // `ZopiqDiskImage` now, which asks `path_provider` for a cache directory
    // and then opens a socket — real I/O, on real futures, which the test
    // binding's fake clock cannot advance. Without `runAsync` the completer
    // simply never resolves and the `Image` sits there for ever: no frame, no
    // error, no fallback. `runAsync` lets the miss actually happen so the
    // failure it produces reaches `errorBuilder`.
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();

    expect(find.byKey(_fallbackKey), findsOneWidget);
  });
}
