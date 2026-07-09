import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zopiqnow/app/zopiq_app.dart';
import 'package:zopiqnow/features/about/presentation/licenses_page.dart';
import 'package:zopiqnow/features/cart/presentation/pages/cart_page.dart';
import 'package:zopiqnow/features/home/data/datasources/restaurant_mock_datasource.dart';
import 'package:zopiqnow/features/home/presentation/home_page.dart';
import 'package:zopiqnow/features/home/presentation/providers/home_providers.dart';
import 'package:zopiqnow/features/menu/data/datasources/menu_mock_datasource.dart';
import 'package:zopiqnow/features/menu/presentation/pages/menu_page.dart';
import 'package:zopiqnow/features/menu/presentation/providers/menu_providers.dart';
import 'package:zopiqnow/features/menu/presentation/widgets/menu_item_tile.dart';

const Duration _latency = Duration(milliseconds: 10);

Widget _app() {
  return ProviderScope(
    overrides: <Override>[
      restaurantDataSourceProvider
          .overrideWithValue(const RestaurantMockDataSource(latency: _latency)),
      menuDataSourceProvider
          .overrideWithValue(const MenuMockDataSource(latency: _latency)),
    ],
    child: const ZopiqApp(),
  );
}

void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Finder _tab(String label) => find.widgetWithText(InkResponse, label);

void main() {
  testWidgets('starts on the Home tab', (WidgetTester tester) async {
    _useTallSurface(tester);
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(HomePage), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Cart'), findsOneWidget);
  });

  testWidgets('the Cart tab shows the empty state and can return to Home',
      (WidgetTester tester) async {
    _useTallSurface(tester);
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(_tab('Cart'));
    await tester.pumpAndSettle();

    expect(find.byType(CartPage), findsOneWidget);
    expect(find.text('Your cart is empty'), findsOneWidget);

    await tester.tap(find.text('Browse restaurants'));
    await tester.pumpAndSettle();

    expect(find.byType(HomePage), findsOneWidget);
  });

  testWidgets('switching tabs preserves the Home scroll position',
      (WidgetTester tester) async {
    _useTallSurface(tester);
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text("What's on your mind?"), findsOneWidget);

    // Scroll the category rail off the top of the viewport.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -1500));
    await tester.pumpAndSettle();
    expect(find.text("What's on your mind?"), findsNothing);

    await tester.tap(_tab('Cart'));
    await tester.pumpAndSettle();
    await tester.tap(_tab('Home'));
    await tester.pumpAndSettle();

    // Still scrolled: an IndexedStack shell keeps the branch alive.
    expect(find.byType(HomePage), findsOneWidget);
    expect(find.text("What's on your mind?"), findsNothing);
  });

  testWidgets('the cart badge tracks the item count',
      (WidgetTester tester) async {
    _useTallSurface(tester);
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(Badge), findsNothing);

    await tester.tap(find.text('Paradise Biryani').first);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(MenuPage), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.ancestor(
          of: find.text('Signature Chicken Biryani'),
          matching: find.byType(MenuItemTile),
        ),
        matching: find.text('ADD'),
      ),
    );
    await tester.pumpAndSettle();

    // The menu sits above the shell, so go back to see the tab bar again.
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.byType(Badge), findsOneWidget);
    expect(find.text('1'), findsWidgets);
  });

  testWidgets('the profile button opens the credits screen',
      (WidgetTester tester) async {
    _useTallSurface(tester);
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.byIcon(Icons.person_rounded));
    await tester.pumpAndSettle();

    expect(find.byType(LicensesPage), findsOneWidget);
    // CC BY-SA 4.0 requires this attribution to be visible in the shipped app.
    expect(find.text('OpenMoji'), findsOneWidget);
    expect(find.textContaining('CC BY-SA 4.0'), findsOneWidget);
  });
}
